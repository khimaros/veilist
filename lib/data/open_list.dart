// a single open list: opens its dht record, folds every member's doc into the
// visible list, watches for live changes, and applies this device's edits to
// its own member doc. a ChangeNotifier so the detail screen rebuilds on any
// local edit or remote change.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/crdt.dart';
import '../models/item_state.dart';
import 'dht_layout.dart';
import 'list_network.dart';
import 'local_list.dart';

/// whether this device's edits have reached the network yet. `local` is a list
/// created here but not yet shared: it lives only on-device (nothing published).
enum SyncStatus { synced, syncing, offline, local }

/// how often the open list does upkeep (sync indicator + reconcile reads).
const Duration _kTickInterval = Duration(seconds: 3);

/// after the first live sync, re-read every Nth tick as a background reconcile.
/// the watch is the fast path, but it can silently drop a change (a coalesced
/// value notification, or a burst of writes a peer flushed on reconnect), so
/// without this a live view could stay stranded an edit behind forever.
const int _kReconcileEveryTicks = 4;

class OpenList extends ChangeNotifier {
  OpenList({
    required this.local,
    required ListNetwork network,
    this.onTitleChanged,
    this.onDocChanged,
    this.onClosed,
    HybridClock? clock,
  }) : _net = network,
       _clock = clock ?? HybridClock.device;

  final LocalList local;
  final ListNetwork _net;

  // shared across this device's lists by default, so a timestamp seen in one
  // list still orders edits made in another.
  final HybridClock _clock;

  /// called when the folded title changes, so the roster cache stays current.
  final void Function(String title)? onTitleChanged;

  /// called with this device's own member doc whenever it changes, so the
  /// roster keeps a copy that does not depend on the dht record store.
  final void Function(String json)? onDocChanged;

  /// called once the list is disposed, so the roster knows it is no longer open.
  final VoidCallback? onClosed;

  // memberIndex -> that member's latest doc.
  final Map<int, MemberDoc> _docs = {};

  String _title = '';
  List<ListItem> _items = const [];
  bool _loading = true;
  Object? _error;
  int _idSeq = 0;
  int _memberCount = 0;
  // content is available to show and edit: either loaded from the local cache
  // on open (a list synced before) or received live this session. a first-ever
  // join with nothing cached stays read-only until this flips.
  bool _loadedFromCache = false;
  // a live network read (or watch change) has landed this session, so the sync
  // indicator can read "synced" rather than "syncing".
  bool _liveSynced = false;
  // this device's own slot is accounted for: we hold the doc already published
  // there, or a whole read says the slot is empty. every write carries a FULL
  // snapshot of that doc, so writing before this is known publishes a doc
  // holding only the newest edit - and since an absent assertion is not a
  // tombstone, everything this device ever contributed ceases to exist for
  // every member (see DESIGN.md "losing a member doc").
  bool _mineResolved = false;
  SyncStatus _sync = SyncStatus.offline;
  int _ticks = 0;
  bool _wasReady = false;
  // the running write loop (null when idle), and whether an edit arrived while
  // it was writing and so needs another pass. see _flush.
  Future<void>? _writes;
  bool _writeAgain = false;
  bool _disposed = false;
  Timer? _syncTimer;
  VoidCallback? _onReadinessChanged;
  StreamSubscription<DocChange>? _changeSub;

  SyncStatus get syncStatus => _sync;

  String get title => _title;
  List<ListItem> get items => _items;

  /// digest of the view as it stands, for the roster's unseen-change mark
  /// (R17): the detail page reports it so looking at a list clears the mark.
  String get digest => foldDigest(_items);
  bool get loading => _loading;
  Object? get error => _error;
  bool get isOwner => local.isOwner;

  /// a list is editable once this device holds its own doc (or knows the slot
  /// is empty) AND there is something to edit - loaded from cache or synced
  /// live - so a re-opened list is usable at once while it revalidates, and
  /// only a first-ever join (nothing cached) waits. an owner needs no data of
  /// anyone else's, but it still may not edit a doc it has not loaded.
  bool get canEdit =>
      _mineResolved && (local.isOwner || _loadedFromCache || _liveSynced);

  /// true while a shared list with nothing to show is still fetching.
  bool get awaitingInitialSync => !canEdit && !_loadedFromCache;

  MemberDoc get _mine => _docs.putIfAbsent(local.memberIndex, MemberDoc.new);

  // a published record always holds at least the creator's doc, so a read that
  // came back with nothing never reached it - however complete the layer below
  // believed it was. trusting such a read is what let a device conclude it was
  // synced with a list it had not read a byte of.
  bool _isWhole(DocsRead read) => read.complete && read.docs.isNotEmpty;

  /// open the record, load current state, and start watching.
  Future<void> open() async {
    try {
      // an unshared list has no dht record and no other member: the on-device
      // doc IS the list, so there is no published slot to write less than.
      if (!local.published) _mineResolved = true;
      // this device's own doc as of its last edit, kept on-device so the dht
      // record store is not the only copy of it. it is what makes the slot
      // resolved before a single read lands, so an unreachable network can
      // never turn the next edit into a wipe.
      final cached = local.localDoc;
      if (cached != null) {
        _receive(local.memberIndex, cached);
        _loadedFromCache = true;
      }
      _memberCount = await _net.openRecord(
        local.recordKey,
        writer: local.writer,
      );
      final read = await _net.readDocs(local.recordKey, _memberCount);
      read.docs.forEach(_receive);
      // cached data (a list synced before) means we can show it and allow edits
      // immediately; a first-ever join with nothing cached waits for the sync.
      if (read.docs.isNotEmpty) _loadedFromCache = true;
      // a whole read that did not carry our slot proves the slot is empty.
      if (_isWhole(read)) _mineResolved = true;
      _changeSub = _net.changes
          .where((c) => c.recordKey == local.recordKey)
          .listen(_onRemoteChange);
      _refold();
      // keep the sync indicator current, and retry the initial read until a
      // live sync lands (a record just opened on a fresh node may not be
      // reachable on the first try).
      _syncTimer = Timer.periodic(_kTickInterval, (_) => _tick());
      // resync when the node (re)connects: the watch only delivers changes that
      // arrive live, so a peer's edit made while we were closed or offline is
      // otherwise never pulled in.
      _onReadinessChanged = _resyncIfReconnected;
      _net.readiness.addListener(_onReadinessChanged!);
      unawaited(_updateSync());
      // a plain read only sees locally-populated subkeys, so a freshly-joined
      // list would show empty. force a network read so shared data loads on
      // open and the indicator reflects real sync, not just "no pending writes".
      unawaited(refresh().catchError((Object _) {}));
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      _notify();
    }
  }

  // periodic upkeep while open: refresh the sync indicator, and re-read - every
  // tick until the first live sync lands, then a slower background reconcile so a
  // change the watch dropped is still pulled in rather than stranding the view.
  void _tick() {
    unawaited(_updateSync());
    if (!_net.isReady) return;
    _ticks++;
    if (!_liveSynced || _ticks % _kReconcileEveryTicks == 0) {
      unawaited(refresh().catchError((Object _) {}));
    }
  }

  // the node reconnected: pull anything that changed while we were offline. the
  // watch only delivers live changes, so a reconnect after any offline gap must
  // re-read - not only before the first live sync. fire on the actual
  // not-ready -> ready edge, not every readiness ping.
  void _resyncIfReconnected() {
    final ready = _net.isReady;
    if (ready && !_wasReady) {
      unawaited(refresh().catchError((Object _) {}));
    }
    _wasReady = ready;
  }

  // a read or a write can outlive the page that started it (see dispose), and
  // renaming from the listing disposes moments after open() kicked off its
  // refresh - so the flag has to be re-checked at the notify itself, not once
  // before the awaits that get us there.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // synced once local writes have flushed to the network; syncing while any are
  // still pending; offline when not connected and nothing is pending.
  Future<void> _updateSync() async {
    if (_disposed) return;
    // a list that has not been shared lives only on this device.
    if (!local.published) {
      if (_sync != SyncStatus.local) {
        _sync = SyncStatus.local;
        _notify();
      }
      return;
    }
    bool pending;
    try {
      pending = await _net.hasPendingWrites(local.recordKey);
    } catch (_) {
      pending = false;
    }
    final SyncStatus next;
    if (!_net.isReady) {
      next = SyncStatus.offline;
    } else if (pending || !_liveSynced) {
      // connected, but either pushing local writes or still receiving the
      // initial data - not yet fully in sync.
      next = SyncStatus.syncing;
    } else {
      next = SyncStatus.synced;
    }
    if (next != _sync) {
      _sync = next;
      _notify();
    }
  }

  /// force a fresh read of every member's doc from the network and re-fold.
  /// used to pull writes that landed before this device was watching (e.g. a
  /// peer wrote while offline to us, so no change event arrives).
  Future<void> refresh() async {
    final read = await _net.readDocs(
      local.recordKey,
      _memberCount,
      forceRefresh: true,
    );
    read.docs.forEach((i, json) {
      // we are the sole authority for our own slot; a network read must not
      // clobber our in-memory contribution, which may hold an edit that has not
      // been flushed yet (e.g. a rename racing the open-time refresh). the one
      // exception is a slot we have not loaded at all: then this read IS how we
      // learn what is already published there, and merging cannot lose an edit.
      if (i == local.memberIndex && _mineResolved) return;
      _receive(i, json);
    });
    _refold();
    // only a read that got EVERY member's subkey means the list is whole. a
    // partial read is a fragment - the remaining members' docs land over the
    // next few reads and visibly rewrite the list - so claiming "synced" here
    // would be a lie, and would drop a first-ever join's spinner onto a
    // half-built list.
    if (_isWhole(read)) {
      _loadedFromCache = true;
      _mineResolved = true;
      if (_net.isReady) _liveSynced = true;
    }
    _notify();
    unawaited(_updateSync());
  }

  void _onRemoteChange(DocChange c) {
    // we are the sole authority for our own slot; ignore the watch echo of our
    // own writes so a late echo cannot clobber a newer in-memory edit.
    if (c.memberIndex == local.memberIndex) return;
    _liveSynced = true; // data landed live from the network
    _receive(c.memberIndex, c.json);
    _refold();
    _notify();
    unawaited(_updateSync());
  }

  Future<void> addItem(String text) async {
    if (!canEdit || text.trim().isEmpty) return;
    _mine.contribution.addItem(_newId(), text.trim(), _now());
    await _flush();
  }

  /// a plain checkbox tap: complete an item, or re-open a completed one.
  Future<void> toggleState(String id) => setItemState(id, _stateOf(id).toggled);

  /// set an item's state outright, from the press-and-hold picker.
  Future<void> setItemState(String id, ItemState state) async {
    if (!canEdit) return;
    _mine.contribution.setState(id, state, _now());
    await _flush();
  }

  ItemState _stateOf(String id) {
    for (final item in _items) {
      if (item.id == id) return item.state;
    }
    return ItemState.unstarted;
  }

  Future<void> setText(String id, String text) async {
    if (!canEdit || text.trim().isEmpty) return;
    _mine.contribution.setText(id, text.trim(), _now());
    await _flush();
  }

  /// move the item at [oldIndex] to [newIndex] (ReorderableListView.onReorderItem
  /// convention: newIndex already accounts for the removed item). reassigns
  /// every item's order in this device's contribution; a fresh ts means this
  /// ordering wins the fold. any member may reorder any item.
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (!canEdit) return;
    final ids = _items.map((i) => i.id).toList();
    if (oldIndex < 0 || oldIndex >= ids.length) return;
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex.clamp(0, ids.length), moved);
    final ts = _now();
    for (var i = 0; i < ids.length; i++) {
      _mine.contribution.setOrder(ids[i], i, ts);
    }
    await _flush();
  }

  Future<void> removeItem(String id) async {
    if (!canEdit) return;
    _mine.contribution.removeItem(id, _now());
    await _flush();
  }

  /// any member can rename a list they can edit; the title is a last-writer-wins
  /// field like item fields, so the latest rename across members wins the fold.
  Future<void> setTitle(String title) async {
    if (!canEdit || title.trim().isEmpty) return;
    _mine.title = Lww(title.trim(), _now());
    await _flush();
  }

  // fold, notify, then push our doc to the network.
  //
  // one write at a time: the dht stamps a write with the sequence number of the
  // value the writer held when the write STARTED, so two overlapping writes to
  // our subkey both go out at the same sequence and only the first survives -
  // the later, newer doc is discarded and nothing tells us. our doc is a full
  // snapshot, so an edit made while a write is in flight does not need a write
  // of its own: re-sending the latest doc once that write lands carries it.
  Future<void> _flush() {
    // never publish a snapshot of a slot we have not accounted for. every
    // caller checks canEdit first, so reaching this means something slipped
    // through - and the cost of the write going out is the whole list.
    if (!_mineResolved) return Future<void>.value();
    _refold();
    // persist our own doc before it goes anywhere: an edit that never reaches
    // the network still survives on this device, and the copy is what keeps the
    // next open from having to trust the network about our own slot.
    onDocChanged?.call(jsonEncode(_mine.toJson()));
    _sync = SyncStatus.syncing;
    _notify();
    if (_writes != null) {
      _writeAgain = true;
      return _writes!;
    }
    return _writes = _writeUntilQuiet();
  }

  Future<void> _writeUntilQuiet() async {
    try {
      do {
        _writeAgain = false;
        await _net.writeDoc(
          local.recordKey,
          local.memberIndex,
          jsonEncode(_mine.toJson()),
        );
      } while (_writeAgain);
    } finally {
      _writes = null;
    }
    unawaited(_updateSync());
  }

  void _refold() {
    final folded = foldDocs(_docs.values);
    final next = folded.title.isEmpty ? local.title : folded.title;
    if (next != _title) {
      _title = next;
      onTitleChanged?.call(next);
    }
    _items = folded.items;
  }

  // decode another member's doc and merge it into the copy we already hold. a
  // dht read can return an OLDER version of a subkey (whichever replica
  // answers), so replacing would walk the view backwards and then forwards
  // again as reads alternate - the "bouncing" this fold exists to prevent.
  // observing the doc's timestamps also advances our clock past anything the
  // peer has done, so our next edit sorts after it however skewed the clocks.
  void _receive(int member, String json) {
    final incoming = MemberDoc.fromJson(
      jsonDecode(json) as Map<String, dynamic>,
    );
    for (final ts in incoming.timestamps) {
      _clock.observe(ts);
    }
    final held = _docs[member];
    _docs[member] = held == null ? incoming : held.mergedWith(incoming);
    if (member == local.memberIndex) _mineResolved = true;
  }

  // ids are unique per device: member index + creation micros + a local seq
  // guards against two adds within the same microsecond.
  String _newId() =>
      '${local.memberIndex}-${DateTime.now().microsecondsSinceEpoch}-${_idSeq++}';

  LogicalTs _now() => _clock.now(local.memberIndex);

  @override
  void dispose() {
    _disposed = true;
    _syncTimer?.cancel();
    if (_onReadinessChanged != null) {
      _net.readiness.removeListener(_onReadinessChanged!);
    }
    _changeSub?.cancel();
    // let a queued write go out before releasing the record: leaving the list
    // right after an edit is ordinary (edit, then straight back to the listing),
    // and a write issued after the record closes fails outright - losing the
    // edit with nothing left to retry it. best-effort: ignore a node already
    // gone.
    final pending = _writes;
    unawaited(
      (pending == null
              ? _net.closeRecord(local.recordKey)
              : pending.then((_) => _net.closeRecord(local.recordKey)))
          .catchError((_) {}),
    );
    onClosed?.call();
    super.dispose();
  }
}

// the roster of lists this device knows, and the operations over it: create,
// join from a share link, share (allocate a fresh member slot), open, delete.
// a ChangeNotifier so the listing page rebuilds as the roster changes.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/crdt.dart';
import 'dht_layout.dart';
import 'list_network.dart';
import 'list_store.dart';
import 'local_list.dart';
import 'local_list_network.dart';
import 'open_list.dart';
import 'share_link.dart';

/// cap on records watched for foreground background-sync at once, to stay under
/// veilid's per-node open-record limit; the rest still sync when opened.
const int kMaxForegroundWatches = 32;

/// how long a published list may go without this device re-writing its own doc.
/// veilid's storage nodes hold other people's records under an lru (128 records
/// a node by default), so a record nobody writes to is eventually evicted from
/// every node holding it and the members can no longer reach each other, each
/// still holding its own copy. nothing else refreshes it.
const Duration kRepublishInterval = Duration(hours: 6);

class ListRepository extends ChangeNotifier {
  ListRepository({required ListStore store, required ListNetwork network})
    : _store = store,
      _network = network;

  final ListStore _store;
  final ListNetwork _network;
  final List<LocalList> _lists = [];

  // distinguishes placeholder keys for unshared local lists created in the same
  // microsecond.
  int _localSeq = 0;

  // foreground background-sync: while the app is foregrounded we watch one
  // record per list (a change marks the list "dirty") and resync each dirty
  // list, so the roster stays current without opening every list by hand.
  bool _foreground = false;
  final Set<String> _watched = {};
  // records with a live OpenList, counted: one list can have two (an open
  // detail page, and a rename from the listing opening its own). a republish
  // must not race a list's own writes - two writes to one subkey go out at the
  // same sequence and the dht silently keeps only the first (see OpenList).
  final Map<String, int> _openCounts = {};
  StreamSubscription<DocChange>? _dirtySub;
  VoidCallback? _onReadinessChanged;

  List<LocalList> get lists => List.unmodifiable(_lists);
  bool get isReady => _network.isReady;

  Future<void> load() async {
    _lists
      ..clear()
      ..addAll(await _store.loadAll());
    _sort();
    notifyListeners();
  }

  /// create a list owned by this device. local and instant (R12): nothing is
  /// published to the dht until the first share (R8), so the creator holds the
  /// list in an on-device doc under a `local:` placeholder key.
  Future<LocalList> createList(String title) async {
    final now = _nowMicros();
    final local = LocalList(
      recordKey: 'local:$now-${_localSeq++}',
      isOwner: true,
      writer: '',
      memberIndex: 0,
      title: title,
      addedAt: now,
      published: false,
      localDoc: jsonEncode(
        MemberDoc(title: Lww(title, LogicalTs(now, 0))).toJson(),
      ),
    );
    await _store.save(local);
    _lists.add(local);
    _sort();
    notifyListeners();
    return local;
  }

  // publish a local-only list to a fresh dht record on its first share: create
  // the record, write the accumulated doc to slot 0, and swap the placeholder
  // identity for the real record.
  Future<void> _publish(LocalList list) async {
    final created = await _network.createRecord();
    final doc =
        list.localDoc ??
        jsonEncode(
          MemberDoc(
            title: Lww(list.title, LogicalTs(_nowMicros(), 0)),
          ).toJson(),
        );
    await _network.openRecord(created.recordKey, writer: created.pool[0]);
    await _network.writeDoc(created.recordKey, 0, doc);
    await _network.closeRecord(created.recordKey);

    final oldKey = list.recordKey;
    list
      ..recordKey = created.recordKey
      ..writer = created.pool[0]
      ..memberPool = created.pool
      ..published = true
      // the doc stays on-device after publishing: it is this device's copy of
      // its own slot, and the record store is no longer the only place it lives.
      ..localDoc = doc
      ..republishedAt = _nowMicros();
    list.assignedSlots.add(0);
    await _store.remove(oldKey);
    await _store.save(list);
    notifyListeners();
  }

  /// join a list from a share link. idempotent: re-joining returns the known
  /// entry. best-effort fetches the title for the listing cache.
  Future<LocalList> joinList(ShareLink link) async {
    final known = _byKey(link.recordKey);
    if (known != null) return known;

    final local = LocalList(
      recordKey: link.recordKey,
      isOwner: false,
      writer: link.writer,
      memberIndex: link.memberIndex,
      title: '',
      addedAt: _nowMicros(),
    );
    try {
      final memberCount = await _network.openRecord(
        local.recordKey,
        writer: local.writer,
      );
      final read = await _network.readDocs(local.recordKey, memberCount);
      // a partial read is fine here: this only warms the roster's cached title,
      // which the open list refreshes anyway.
      local.title = foldDocs(read.docs.values.map(_decodeDoc)).title;
      await _network.closeRecord(local.recordKey);
    } catch (_) {
      // offline join; the title fills in the first time the list is opened.
    }

    await _store.save(local);
    _lists.add(local);
    _sort();
    notifyListeners();
    // adopt into foreground sync (if active) so a peer's later edits reach the
    // listing even before this list is opened.
    unawaited(_syncDirty(local.recordKey));
    return local;
  }

  /// build a share link. the creator allocates a fresh unused slot so each
  /// invitee is an attributable, individually ignorable member; once the pool
  /// is exhausted (or for non-creators) it shares this device's own slot.
  Future<ShareLink> shareList(LocalList list) async {
    // the first share of a local-only list publishes it to a real dht record.
    if (list.isOwner && !list.published) await _publish(list);
    if (list.isOwner) {
      final slot = _nextFreeSlot(list);
      if (slot != null) {
        list.assignedSlots.add(slot);
        await _store.save(list);
        return ShareLink(
          recordKey: list.recordKey,
          writer: list.memberPool[slot],
          memberIndex: slot,
        );
      }
    }
    return ShareLink(
      recordKey: list.recordKey,
      writer: list.writer,
      memberIndex: list.memberIndex,
    );
  }

  Future<void> deleteList(LocalList list) async {
    if (list.published) {
      try {
        await _network.deleteRecord(list.recordKey);
      } catch (_) {
        // local removal still proceeds even if the network delete fails.
      }
    }
    await _store.remove(list.recordKey);
    _lists.removeWhere((l) => l.recordKey == list.recordKey);
    notifyListeners();
  }

  OpenList open(LocalList list) {
    // the key is captured: publishing re-keys the list, and this open must be
    // released under the key it was taken out on.
    final key = list.recordKey;
    _openCounts.update(key, (n) => n + 1, ifAbsent: () => 1);
    return OpenList(
      local: list,
      network: _networkFor(list),
      onTitleChanged: (t) => _updateCachedTitle(list, t),
      onDocChanged: (json) => _saveDoc(list, json),
      onClosed: () => _release(key),
    );
  }

  void _release(String key) {
    final remaining = (_openCounts[key] ?? 0) - 1;
    if (remaining > 0) {
      _openCounts[key] = remaining;
    } else {
      _openCounts.remove(key);
    }
  }

  // keep this device's own doc on-device, alongside the dht record rather than
  // only inside it, and note that the record was just written to.
  void _saveDoc(LocalList list, String json) {
    list
      ..localDoc = json
      ..republishedAt = _nowMicros();
    unawaited(_store.save(list));
  }

  // an unpublished list is backed by a local-only network so its edits persist
  // on-device without touching the dht; a published one uses the real network.
  ListNetwork _networkFor(LocalList list) => list.published
      ? _network
      : LocalListNetwork(
          doc: list.localDoc,
          onWrite: (json) {
            list.localDoc = json;
            _store.save(list);
          },
        );

  /// rename from the listing. any member may rename (the title is a last-writer-
  /// wins field). reuses OpenList so the write, fold and cache update match the
  /// detail page, and publishes so other clients see it via foreground sync.
  Future<void> renameList(LocalList list, String title) async {
    final opened = open(list);
    try {
      await opened.open();
      // a list must have synced at least once before it is editable: renaming
      // writes this device's whole doc, so it must hold that doc first.
      if (!opened.canEdit) await opened.refresh().catchError((_) {});
      await opened.setTitle(title);
    } finally {
      opened.dispose();
    }
  }

  void _updateCachedTitle(LocalList list, String title) {
    if (title.isEmpty || list.title == title) return;
    list.title = title;
    _store.save(list);
    notifyListeners();
  }

  /// begin keeping every roster list synchronized while the app is foregrounded:
  /// watch one record per list (a change marks it dirty) and resync each dirty
  /// list, so the roster stays current without opening every list by hand.
  Future<void> startForegroundSync() async {
    if (_foreground) return;
    _foreground = true;
    _dirtySub ??= _network.changes.listen((c) => _syncDirty(c.recordKey));
    _onReadinessChanged ??= () {
      if (_foreground && _network.isReady) unawaited(_syncAll());
    };
    _network.readiness.addListener(_onReadinessChanged!);
    await _syncAll();
  }

  /// stop foreground sync and release every watched record.
  Future<void> stopForegroundSync() async {
    if (!_foreground) return;
    _foreground = false;
    await _dirtySub?.cancel();
    _dirtySub = null;
    if (_onReadinessChanged != null) {
      _network.readiness.removeListener(_onReadinessChanged!);
    }
    for (final key in _watched.toList()) {
      await _network.closeRecord(key).catchError((_) {});
    }
    _watched.clear();
  }

  // sync every list (up to the watch cap) so each has a live watch and a warm
  // local cache. called on foreground and on reconnect.
  Future<void> _syncAll() async {
    if (!_network.isReady) return;
    if (_lists.length > kMaxForegroundWatches) {
      debugPrint(
        'foreground sync watches $kMaxForegroundWatches of '
        '${_lists.length} lists; the rest sync when opened',
      );
    }
    // snapshot the keys: _syncDirty awaits network i/o, during which the roster
    // can be mutated (a create/join/share re-key, another readiness-triggered
    // sync), which would otherwise throw "concurrent modification".
    final keys = _lists.take(kMaxForegroundWatches).map((l) => l.recordKey);
    for (final recordKey in keys.toList()) {
      await _syncDirty(recordKey);
    }
  }

  // open (and keep open, so the watch stays live) then re-read one list from the
  // network, refreshing its cached title.
  Future<void> _syncDirty(String recordKey) async {
    if (!_foreground || !_network.isReady) return;
    final list = _byKey(recordKey);
    // an unpublished list has no dht record to watch or read.
    if (list == null || !list.published) return;
    try {
      if (!_watched.contains(recordKey)) {
        await _network.openRecord(recordKey, writer: list.writer);
        _watched.add(recordKey);
      }
      final read = await _network.readDocs(
        recordKey,
        kMaxMembers,
        forceRefresh: true,
      );
      _updateCachedTitle(
        list,
        foldDocs(read.docs.values.map(_decodeDoc)).title,
      );
      await _republishIfStale(list);
    } catch (_) {
      // unreachable for now; a later change or reconnect retries.
    }
  }

  // re-write this device's own doc so the storage nodes holding the record keep
  // it. a record nobody writes to is evicted, and then the members can no
  // longer reach each other however online they are. skipped while the list is
  // open, so this never races that list's own writes.
  Future<void> _republishIfStale(LocalList list) async {
    final doc = list.localDoc;
    if (doc == null || _openCounts.containsKey(list.recordKey)) return;
    final now = _nowMicros();
    if (now - list.republishedAt < kRepublishInterval.inMicroseconds) return;
    await _network.writeDoc(list.recordKey, list.memberIndex, doc);
    list.republishedAt = now;
    await _store.save(list);
  }

  int? _nextFreeSlot(LocalList list) {
    for (var i = 0; i < list.memberPool.length; i++) {
      if (!list.assignedSlots.contains(i)) return i;
    }
    return null;
  }

  LocalList? _byKey(String recordKey) {
    for (final l in _lists) {
      if (l.recordKey == recordKey) return l;
    }
    return null;
  }

  MemberDoc _decodeDoc(String json) =>
      MemberDoc.fromJson(jsonDecode(json) as Map<String, dynamic>);

  void _sort() => _lists.sort((a, b) => b.addedAt.compareTo(a.addedAt));

  int _nowMicros() => DateTime.now().microsecondsSinceEpoch;
}

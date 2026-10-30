// the network surface a list needs: create a record, open it as a writer, read
// every member's doc, write our own, and receive live changes. an interface so
// widget/integration tests run against an in-memory fake while production uses
// veilid dht records (see DESIGN.md).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:veilid/veilid.dart';

import 'dht_layout.dart';
import '../veilid/veilid_service.dart';

/// a live change to one member's doc, delivered from a watch.
typedef DocChange = ({String recordKey, int memberIndex, String json});

/// the result of creating a record: its key and the full member keypair pool
/// (the creator keeps every slot's keypair to hand out on sharing).
typedef CreatedRecord = ({String recordKey, List<String> pool});

/// the result of reading a record: the member docs this read could fetch, and
/// whether that is everything the network holds. a read is INCOMPLETE when some
/// member's subkey could not be fetched this time - a fresh joiner's network
/// inspect comes back TryAgain until the record is reachable, and each subkey
/// read can fail on its own. an incomplete read is a fragment of the list, so a
/// reader must not present it as fully synced (see OpenList).
typedef DocsRead = ({Map<int, String> docs, bool complete});

/// stage of a network [ListNetwork.readDocs] pass.
enum ReadStage { inspecting, fetching }

/// progress of an in-flight network read: inspecting subkey sequences, then
/// fetching the [total] member subkeys whose network sequence moved ahead.
typedef ReadProgress = ({ReadStage stage, int fetched, int total});

typedef ReadProgressCallback = void Function(ReadProgress progress);

/// retries for an online openDHTRecord that transiently returns TryAgain.
const int _kOpenReadyRetries = 2;
const Duration _kOpenRetryDelay = Duration(milliseconds: 500);

/// only the even member data subkeys carry docs (see dht_layout.dart); skipping
/// the reserved odd subkeys halves the subkeys an inspect must gather consensus
/// across.
final List<ValueSubkeyRange> _kMemberDataSubkeys = List.unmodifiable([
  for (var i = 0; i < kMaxMembers; i++)
    ValueSubkeyRange.single(memberDataSubkey(i)),
]);

typedef _SubkeySeqs = ({
  Map<int, int> local,
  Map<int, int> network,
  bool fromNetwork,
});

abstract class ListNetwork {
  bool get isReady;

  /// human-readable connection stage while not yet [isReady], or null when
  /// ready.
  String? get connectingDetail;

  /// notifies when [isReady] may have changed, so an open list can resync when
  /// the node (re)connects and pull changes it missed while offline or closed.
  Listenable get readiness;

  Future<CreatedRecord> createRecord();

  /// open [recordKey] with [writer]; returns the schema's member count.
  Future<int> openRecord(String recordKey, {required String writer});

  /// read each member's doc json (only members that have written appear), plus
  /// whether the read got everything. set [forceRefresh] to pull the latest
  /// from the network rather than local; only a network read can be complete.
  Future<DocsRead> readDocs(
    String recordKey,
    int memberCount, {
    bool forceRefresh = false,
    ReadProgressCallback? onProgress,
  });

  /// one member's doc, asked of the network directly, or null if it holds none.
  /// slower than [readDocs] on an empty slot, and the only answer strong enough
  /// to publish over: see OpenList._confirmMine.
  Future<String?> readMemberDoc(String recordKey, int memberIndex);

  Future<void> writeDoc(String recordKey, int memberIndex, String json);

  /// changes from all open records; consumers filter by record key.
  Stream<DocChange> get changes;

  /// true if this record has local writes not yet flushed to the network.
  Future<bool> hasPendingWrites(String recordKey);

  Future<void> closeRecord(String recordKey);
  Future<void> deleteRecord(String recordKey);
}

/// veilid dht implementation. one SMPL record per list; member i reads/writes
/// subkey `memberDataSubkey(i)`.
class VeilidListNetwork implements ListNetwork {
  VeilidListNetwork(
    this._service, {
    VeilidRoutingContext Function()? routingContext,
  }) : _routingContext = routingContext;

  final VeilidService _service;
  final VeilidRoutingContext Function()? _routingContext;

  // veilid keys opened_records by record key with no refcount: a second
  // openDHTRecord overwrites the entry, and a single closeDHTRecord removes it
  // and cancels its watch. refcounting here lets the foreground sync and an
  // open detail page watch the same record without one's close tearing down the
  // other's watch. the underlying record opens once and closes on the last ref.
  final Map<String, int> _openRefs = {};
  final Map<String, int> _memberCounts = {};
  final Map<String, _InFlightRead> _inFlightReads = {};

  VeilidRoutingContext get _rc =>
      _routingContext != null ? _routingContext() : _service.routingContext;

  @override
  bool get isReady => _service.isReady;

  @override
  String? get connectingDetail => _service.connectingDetail;

  // the service is a ChangeNotifier that notifies on every phase change.
  @override
  Listenable get readiness => _service;

  @override
  Future<CreatedRecord> createRecord() async {
    final pool = <KeyPair>[
      for (var i = 0; i < kMaxMembers; i++)
        await Veilid.instance.generateKeyPair(bestCryptoKind),
    ];
    final members = <DHTSchemaMember>[
      for (final kp in pool)
        await DHTSchemaMember.fromPublicKey(
          Veilid.instance,
          kp.key,
          kSubkeysPerMember,
        ),
    ];
    final schema = DHTSchema.smpl(oCnt: kOwnerSubkeys, members: members);
    final desc = await _rc.createDHTRecord(bestCryptoKind, schema);
    // release the create-time (owner) open; the list opens fresh as a member
    // writer, since with oCnt=0 we never write owner subkeys.
    await _rc.closeDHTRecord(desc.key);
    return (
      recordKey: desc.key.toString(),
      pool: [for (final kp in pool) kp.toString()],
    );
  }

  @override
  Future<int> openRecord(String recordKey, {required String writer}) async {
    final refs = _openRefs[recordKey] ?? 0;
    if (refs == 0) {
      final key = RecordKey.fromString(recordKey);
      final kp = KeyPair.fromString(writer);
      // opening a record this node has never seen requires a network inspect,
      // which returns TryAgain until the record is reachable. a fresh joiner
      // hits this every time, so retry rather than give up (which would leave
      // us with zero members and read nothing).
      final desc = await _openWithRetry(key, kp);
      // watch every subkey so any member's edits push a change to us.
      await _rc.watchDHTValues(key);
      final schema = desc.schema;
      final count = schema is DHTSchemaSMPL ? schema.members.length : 0;
      debugPrint('VEILIST_OPEN members=$count schema=${schema.runtimeType}');
      _memberCounts[recordKey] = count;
    }
    _openRefs[recordKey] = refs + 1;
    return _memberCounts[recordKey] ?? 0;
  }

  Future<DHTRecordDescriptor> _openWithRetry(RecordKey key, KeyPair kp) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _rc.openDHTRecord(key, writer: kp);
      } on VeilidAPIExceptionTryAgain {
        // fail fast when offline; OpenList and ListRepository retry on
        // readiness and periodic ticks instead of blocking callers for 60s.
        if (!isReady || attempt >= _kOpenReadyRetries) rethrow;
        await Future<void>.delayed(_kOpenRetryDelay);
      }
    }
  }

  @override
  Future<DocsRead> readDocs(
    String recordKey,
    int memberCount, {
    bool forceRefresh = false,
    ReadProgressCallback? onProgress,
  }) async {
    if (!forceRefresh) {
      return _readDocsOnce(
        recordKey,
        memberCount,
        forceRefresh: false,
        onProgress: onProgress,
      );
    }
    final existing = _inFlightReads[recordKey];
    if (existing != null) {
      existing.attach(onProgress);
      return _sliceDocs(await existing.future!, memberCount);
    }
    final flight = _InFlightRead()..attach(onProgress);
    final future = _readDocsOnce(
      recordKey,
      kMaxMembers,
      forceRefresh: true,
      onProgress: flight.emit,
    );
    flight.future = future;
    _inFlightReads[recordKey] = flight;
    try {
      return _sliceDocs(await future, memberCount);
    } finally {
      _inFlightReads.remove(recordKey);
    }
  }

  DocsRead _sliceDocs(DocsRead read, int memberCount) {
    if (memberCount >= kMaxMembers) return read;
    return (
      docs: {
        for (final e in read.docs.entries)
          if (e.key < memberCount) e.key: e.value,
      },
      complete: read.complete,
    );
  }

  Future<DocsRead> _readDocsOnce(
    String recordKey,
    int memberCount, {
    required bool forceRefresh,
    ReadProgressCallback? onProgress,
  }) async {
    final key = RecordKey.fromString(recordKey);
    final watch = Stopwatch()..start();
    if (forceRefresh) {
      onProgress?.call((stage: ReadStage.inspecting, fetched: 0, total: 0));
    }
    final populated = await _populatedSubkeys(key, network: forceRefresh);
    // read every subkey EITHER view knows to hold a value. storage nodes keep
    // other people's records under an lru, so a list nobody has written to for
    // days is evicted from every node holding it; reading only what the network
    // still knows about would make that list come back empty even though this
    // node holds every doc.
    final held = {...populated.local.keys, ...populated.network.keys};
    // the whole picture only when the network answered AND knew about
    // everything this node does.
    final completeInspect =
        populated.fromNetwork &&
        held.isNotEmpty &&
        populated.network.keys.toSet().containsAll(populated.local.keys);
    final fetched = await _fetchHeldDocs(
      key,
      memberCount,
      held: held,
      populated: populated,
      forceRefresh: forceRefresh,
      onProgress: onProgress,
    );
    final complete = completeInspect && fetched.complete;
    debugPrint(
      'VEILIST_READ ${_short(recordKey)} force=$forceRefresh '
      'docs=${fetched.docs.length} complete=$complete '
      'local=${populated.local.length} '
      'network=${populated.fromNetwork ? populated.network.length : '-'} '
      'ms=${watch.elapsedMilliseconds}',
    );
    return (docs: fetched.docs, complete: complete);
  }

  // fetch every held member slot in parallel, hitting the network only for
  // subkeys whose network sequence moved past what this node already holds.
  Future<DocsRead> _fetchHeldDocs(
    RecordKey key,
    int memberCount, {
    required Set<int> held,
    required _SubkeySeqs populated,
    required bool forceRefresh,
    ReadProgressCallback? onProgress,
  }) async {
    bool needsNetwork(int sk) {
      if (!forceRefresh || !populated.fromNetwork) return false;
      final netSeq = populated.network[sk];
      if (netSeq == null) return false;
      final localSeq = populated.local[sk];
      return localSeq == null || netSeq > localSeq;
    }

    final slots = [
      for (var i = 0; i < memberCount; i++)
        if (held.contains(memberDataSubkey(i))) i,
    ];
    final total = slots.where((i) => needsNetwork(memberDataSubkey(i))).length;
    if (forceRefresh) {
      onProgress?.call((stage: ReadStage.fetching, fetched: 0, total: total));
    }
    var complete = true;
    var done = 0;
    final raw = <int, String>{};
    await Future.wait(
      slots.map((i) async {
        final sk = memberDataSubkey(i);
        final fromNet = needsNetwork(sk);
        try {
          var v = await _rc.getDHTValue(key, sk, forceRefresh: fromNet);
          if (v == null && !fromNet && forceRefresh && populated.fromNetwork) {
            v = await _rc.getDHTValue(key, sk, forceRefresh: true);
          }
          if (v != null) {
            raw[i] = utf8.decode(v.data);
          } else {
            complete = false;
          }
        } on VeilidAPIExceptionTryAgain {
          complete = false;
        } finally {
          if (fromNet) {
            done++;
            onProgress?.call((
              stage: ReadStage.fetching,
              fetched: done,
              total: total,
            ));
          }
        }
      }),
    );
    return (
      docs: {
        for (final i in slots)
          if (raw.containsKey(i)) i: raw[i]!,
      },
      complete: complete,
    );
  }

  @override
  Future<String?> readMemberDoc(String recordKey, int memberIndex) async {
    final v = await _rc.getDHTValue(
      RecordKey.fromString(recordKey),
      memberDataSubkey(memberIndex),
      forceRefresh: true,
    );
    return v == null ? null : utf8.decode(v.data);
  }

  // enough of a record key to tell lists apart in a log, and no more of it.
  String _short(String recordKey) => recordKey.substring(recordKey.length - 6);

  // sequence numbers per populated subkey, locally and on the network.
  Future<_SubkeySeqs> _populatedSubkeys(
    RecordKey key, {
    required bool network,
  }) async {
    DHTRecordReport report;
    var useNetwork = network;
    try {
      report = await _rc.inspectDHTRecord(
        key,
        subkeys: _kMemberDataSubkeys,
        scope: network ? DHTReportScope.syncGet : DHTReportScope.local,
      );
    } on VeilidAPIExceptionTryAgain {
      useNetwork = false;
      report = await _rc.inspectDHTRecord(key, subkeys: _kMemberDataSubkeys);
    }
    return (
      local: _seqBySubkey(report, report.localSeqs),
      network: useNetwork
          ? _seqBySubkey(report, report.networkSeqs)
          : const <int, int>{},
      fromNetwork: useNetwork,
    );
  }

  Map<int, int> _seqBySubkey(DHTRecordReport report, List<int?> seqs) {
    final result = <int, int>{};
    var j = 0;
    for (final range in report.subkeys) {
      for (var sk = range.low; sk <= range.high; sk++, j++) {
        final seq = j < seqs.length ? seqs[j] : null;
        if (seq != null) result[sk] = seq;
      }
    }
    return result;
  }

  @override
  Future<void> writeDoc(String recordKey, int memberIndex, String json) async {
    final key = RecordKey.fromString(recordKey);
    final watch = Stopwatch()..start();
    await _rc.setDHTValue(
      key,
      memberDataSubkey(memberIndex),
      Uint8List.fromList(utf8.encode(json)),
    );
    debugPrint(
      'VEILIST_WRITE ${_short(recordKey)} member=$memberIndex '
      'ms=${watch.elapsedMilliseconds}',
    );
  }

  @override
  Stream<DocChange> get changes =>
      _service.valueChanges.asyncExpand(_toChanges);

  // map a watch update to per-member doc changes. veilid includes the changed
  // value inline only for a single-subkey change; when it coalesces several
  // subkeys changed within one flush window (two members editing at once) it
  // sends no inline value and expects the reader to re-read the range. fetch
  // those subkeys ourselves rather than dropping the update - dropping it left a
  // concurrent edit invisible until veilid's ~30s fallback inspection.
  Stream<DocChange> _toChanges(VeilidUpdateValueChange u) async* {
    final key = u.key;
    final inline = u.value?.data;
    for (final range in u.subkeys) {
      for (var sk = range.low; sk <= range.high; sk++) {
        if (sk % kSubkeysPerMember != 0) continue;
        var data = inline;
        if (data == null) {
          try {
            data = (await _rc.getDHTValue(key, sk, forceRefresh: true))?.data;
          } on VeilidAPIExceptionTryAgain {
            // transient; retried on the next update or a periodic refresh.
          }
        }
        debugPrint(
          'VEILIST_CHANGE ${_short(key.toString())} '
          'member=${sk ~/ kSubkeysPerMember} inline=${inline != null} '
          'got=${data != null}',
        );
        if (data != null) {
          yield (
            recordKey: key.toString(),
            memberIndex: sk ~/ kSubkeysPerMember,
            json: utf8.decode(data),
          );
        }
      }
    }
  }

  @override
  Future<bool> hasPendingWrites(String recordKey) async {
    try {
      final report = await _rc.inspectDHTRecord(
        RecordKey.fromString(recordKey),
      );
      return report.offlineSubkeys.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> closeRecord(String recordKey) async {
    final refs = _openRefs[recordKey] ?? 0;
    if (refs == 0) return;
    if (refs > 1) {
      _openRefs[recordKey] = refs - 1;
      return;
    }
    _openRefs.remove(recordKey);
    _memberCounts.remove(recordKey);
    await _rc.closeDHTRecord(RecordKey.fromString(recordKey));
  }

  @override
  Future<void> deleteRecord(String recordKey) async {
    final key = RecordKey.fromString(recordKey);
    _openRefs.remove(recordKey);
    _memberCounts.remove(recordKey);
    await _rc.closeDHTRecord(key);
    await _rc.deleteDHTRecord(key);
  }
}

class _InFlightRead {
  Future<DocsRead>? future;
  final List<ReadProgressCallback> _listeners = [];
  ReadProgress? _latest;

  void attach(ReadProgressCallback? cb) {
    if (cb == null) return;
    _listeners.add(cb);
    if (_latest != null) cb(_latest!);
  }

  void emit(ReadProgress progress) {
    _latest = progress;
    for (final cb in _listeners) {
      cb(progress);
    }
  }
}

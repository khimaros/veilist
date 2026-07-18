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

abstract class ListNetwork {
  bool get isReady;

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
  });

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
  VeilidListNetwork(this._service);

  final VeilidService _service;

  // veilid keys opened_records by record key with no refcount: a second
  // openDHTRecord overwrites the entry, and a single closeDHTRecord removes it
  // and cancels its watch. refcounting here lets the foreground sync and an
  // open detail page watch the same record without one's close tearing down the
  // other's watch. the underlying record opens once and closes on the last ref.
  final Map<String, int> _openRefs = {};
  final Map<String, int> _memberCounts = {};

  VeilidRoutingContext get _rc => _service.routingContext;

  @override
  bool get isReady => _service.isReady;

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
        if (attempt >= 30) rethrow;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  @override
  Future<DocsRead> readDocs(
    String recordKey,
    int memberCount, {
    bool forceRefresh = false,
  }) async {
    final key = RecordKey.fromString(recordKey);
    // only read subkeys that actually hold a value. calling getDHTValue on an
    // empty subkey triggers a blocking network fanout, which hangs the ui while
    // the node is still connecting; a local inspect is non-blocking and tells us
    // which subkeys to bother reading.
    final populated = await _populatedSubkeys(key, network: forceRefresh);
    // a local read only ever shows what this node happens to hold, so it is
    // never the whole picture; a network read is, unless a subkey slips.
    var complete = populated.fromNetwork;
    final docs = <int, String>{};
    for (var i = 0; i < memberCount; i++) {
      final sk = memberDataSubkey(i);
      if (!populated.subkeys.contains(sk)) continue;
      try {
        final v = await _rc.getDHTValue(key, sk, forceRefresh: forceRefresh);
        if (v != null) {
          docs[i] = utf8.decode(v.data);
        } else {
          complete = false; // the inspect saw a value we could not fetch
        }
      } on VeilidAPIExceptionTryAgain {
        // transient; this subkey is retried on the next read.
        complete = false;
      }
    }
    return (docs: docs, complete: complete);
  }

  // subkeys that currently hold a value, from a non-blocking local inspect (or
  // a network inspect when [network] and reachable). `fromNetwork` says which
  // view answered: the network inspect returns TryAgain until a freshly opened
  // record is reachable, and the local fallback only knows what this node has
  // already fetched.
  Future<({Set<int> subkeys, bool fromNetwork})> _populatedSubkeys(
    RecordKey key, {
    required bool network,
  }) async {
    DHTRecordReport report;
    var useNetwork = network;
    try {
      report = await _rc.inspectDHTRecord(
        key,
        scope: network ? DHTReportScope.syncGet : DHTReportScope.local,
      );
    } on VeilidAPIExceptionTryAgain {
      useNetwork = false;
      report = await _rc.inspectDHTRecord(key);
    }
    final seqs = useNetwork ? report.networkSeqs : report.localSeqs;
    final result = <int>{};
    var j = 0;
    for (final range in report.subkeys) {
      for (var sk = range.low; sk <= range.high; sk++, j++) {
        if (j < seqs.length && seqs[j] != null) result.add(sk);
      }
    }
    return (subkeys: result, fromNetwork: useNetwork);
  }

  @override
  Future<void> writeDoc(String recordKey, int memberIndex, String json) async {
    final key = RecordKey.fromString(recordKey);
    await _rc.setDHTValue(
      key,
      memberDataSubkey(memberIndex),
      Uint8List.fromList(utf8.encode(json)),
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

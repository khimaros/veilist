// tests VeilidListNetwork's dht interaction: narrow subkey inspection,
// sequence-aware local vs network reads, parallel stale fetches, coalesced
// concurrent forced reads, and fast failure when unready.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veilid/veilid.dart';
import 'package:veilist/data/dht_layout.dart';
import 'package:veilist/data/list_network.dart';
import 'package:veilist/veilid/veilid_service.dart';

const String _kRecordKey = 'VLD0:aXQtaXMtYS1yZWNvcmQta2V5';
const String _kWriterKey = 'VLD0:cHVibGljLWtleQ:c2VjcmV0LWtleQ';
const String _kOwnerKey = 'VLD0:b3duZXIta2V5';

// minimal routing context fake recording inspect and get calls.
class _FakeRoutingContext implements VeilidRoutingContext {
  List<ValueSubkeyRange>? lastInspectedSubkeys;
  int inspectCalls = 0;
  final List<({int subkey, bool forceRefresh})> gets = [];
  int inFlightGets = 0;
  int maxInFlightGets = 0;
  Duration getDelay = Duration.zero;
  Completer<void>? inspectGate;
  bool failOpenWithTryAgain = false;

  Map<int, int> localSeqs = {};
  Map<int, int> networkSeqs = {};
  Map<int, String> values = {};

  @override
  Future<DHTRecordDescriptor> openDHTRecord(
    RecordKey key, {
    KeyPair? writer,
  }) async {
    if (failOpenWithTryAgain) {
      throw const VeilidAPIExceptionTryAgain('offline');
    }
    return DHTRecordDescriptor(
      key: key,
      owner: PublicKey.fromString(_kOwnerKey),
      schema: DHTSchema.smpl(
        oCnt: kOwnerSubkeys,
        members: [
          for (var i = 0; i < kMaxMembers; i++)
            DHTSchemaMember(
              mKey: BareMemberId.fromBytes(Uint8List(32)),
              mCnt: kSubkeysPerMember,
            ),
        ],
      ),
    );
  }

  @override
  Future<bool> watchDHTValues(
    RecordKey key, {
    List<ValueSubkeyRange>? subkeys,
    Timestamp? expiration,
    int? count,
  }) async => true;

  @override
  Future<DHTRecordReport> inspectDHTRecord(
    RecordKey key, {
    List<ValueSubkeyRange>? subkeys,
    DHTReportScope scope = DHTReportScope.local,
  }) async {
    inspectCalls++;
    lastInspectedSubkeys = subkeys;
    await inspectGate?.future;
    final ranges =
        subkeys ??
        [
          const ValueSubkeyRange(
            low: 0,
            high: kMaxMembers * kSubkeysPerMember - 1,
          ),
        ];
    final local = <int?>[];
    final network = <int?>[];
    for (final r in ranges) {
      for (var sk = r.low; sk <= r.high; sk++) {
        local.add(localSeqs[sk]);
        network.add(scope == DHTReportScope.local ? null : networkSeqs[sk]);
      }
    }
    return DHTRecordReport(
      subkeys: ranges,
      offlineSubkeys: const [],
      localSeqs: local,
      networkSeqs: network,
    );
  }

  @override
  Future<ValueData?> getDHTValue(
    RecordKey key,
    int subkey, {
    bool forceRefresh = false,
  }) async {
    gets.add((subkey: subkey, forceRefresh: forceRefresh));
    inFlightGets++;
    if (inFlightGets > maxInFlightGets) maxInFlightGets = inFlightGets;
    try {
      if (getDelay > Duration.zero) await Future<void>.delayed(getDelay);
      final text = values[subkey];
      if (text == null) return null;
      return ValueData(
        seq: networkSeqs[subkey] ?? localSeqs[subkey] ?? 0,
        data: Uint8List.fromList(utf8.encode(text)),
        writer: PublicKey.fromString(_kOwnerKey),
      );
    } finally {
      inFlightGets--;
    }
  }

  @override
  Future<void> closeDHTRecord(RecordKey key) async {}

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('forced readDocs inspects only member data subkeys', () async {
    final rc = _FakeRoutingContext()
      ..networkSeqs = {0: 0}
      ..values = {0: '{"i":{}}'};
    final net = VeilidListNetwork(
      VeilidService.instance,
      routingContext: () => rc,
    );

    await net.readDocs(_kRecordKey, kMaxMembers, forceRefresh: true);

    expect(rc.lastInspectedSubkeys, [
      for (var i = 0; i < kMaxMembers; i++)
        ValueSubkeyRange.single(memberDataSubkey(i)),
    ]);
  });

  test('forced readDocs reads locally when localSeq matches networkSeq and '
      'fetches stale subkeys in parallel', () async {
    final rc = _FakeRoutingContext()
      ..localSeqs = {0: 3, 2: 1}
      ..networkSeqs = {0: 3, 2: 2, 4: 0}
      ..values = {0: '{"i":{}}', 2: '{"i":{}}', 4: '{"i":{}}'}
      ..getDelay = const Duration(milliseconds: 20);
    final net = VeilidListNetwork(
      VeilidService.instance,
      routingContext: () => rc,
    );

    final read = await net.readDocs(
      _kRecordKey,
      kMaxMembers,
      forceRefresh: true,
    );

    expect(read.complete, isTrue);
    expect(read.docs.keys, containsAll([0, 1, 2]));
    // subkey 0 already has seq 3 locally, so it must not fan out to the dht.
    expect(rc.gets.where((g) => g.subkey == 0).single.forceRefresh, isFalse);
    // subkeys 2 and 4 are stale/missing locally and must fetch concurrently.
    expect(rc.maxInFlightGets, greaterThan(1));
  });

  test(
    'concurrent forced readDocs on one record coalesce into one inspect',
    () async {
      final gate = Completer<void>();
      final rc = _FakeRoutingContext()
        ..inspectGate = gate
        ..networkSeqs = {0: 0}
        ..values = {0: '{"i":{}}'};
      final net = VeilidListNetwork(
        VeilidService.instance,
        routingContext: () => rc,
      );

      final a = net.readDocs(_kRecordKey, kMaxMembers, forceRefresh: true);
      final b = net.readDocs(_kRecordKey, kMaxMembers, forceRefresh: true);
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      final results = await Future.wait([a, b]);

      expect(rc.inspectCalls, 1);
      expect(results[0].docs, results[1].docs);
    },
  );

  test('openRecord fails immediately instead of sleeping when unready', () {
    fakeAsync((async) {
      final rc = _FakeRoutingContext()..failOpenWithTryAgain = true;
      // a fresh VeilidService starts in stopped (!isReady).
      final net = VeilidListNetwork(
        VeilidService.instance,
        routingContext: () => rc,
      );

      Object? caught;
      unawaited(
        net.openRecord(_kRecordKey, writer: _kWriterKey).catchError((Object e) {
          caught = e;
          return 0;
        }),
      );
      async.flushMicrotasks();

      expect(caught, isA<VeilidAPIExceptionTryAgain>());
      expect(async.pendingTimers, isEmpty);
    });
  });
}

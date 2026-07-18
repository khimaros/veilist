// sync behaviour of a single OpenList: cross-member ordering converges, and a
// change a peer made while this client was closed must appear once the node
// finishes attaching. the second test reproduces the reopen-does-not-resync bug
// (a reorder synced peer-to-peer but not to a client that was closed at the
// time and cold-starts on reopen).

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veilist/data/dht_layout.dart';
import 'package:veilist/data/list_network.dart';
import 'package:veilist/data/local_list.dart';
import 'package:veilist/data/open_list.dart';
import 'package:veilist/models/crdt.dart';

import '../fakes/fake_backend.dart';

// let broadcast change events and unawaited refreshes flush.
Future<void> settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

// a fake network that can be unreachable, like a veilid node that is still
// attaching: reads return nothing until setReady(true) flips it online.
class LatentNetwork extends FakeListNetwork {
  LatentNetwork(super.dht);

  @override
  Future<DocsRead> readDocs(
    String recordKey,
    int memberCount, {
    bool forceRefresh = false,
  }) async => isReady
      ? super.readDocs(recordKey, memberCount, forceRefresh: forceRefresh)
      : (docs: const <int, String>{}, complete: false);
}

// a fake network that reads a record the way a fresh joiner does: the open-time
// local read sees nothing (nothing is cached yet), the first network read
// reaches only some members' subkeys - veilid's network inspect can come back
// TryAgain, so the layer falls back to the local view of which subkeys hold
// data, and each subkey read can fail on its own - and later reads see it all.
class PartialReadNetwork extends FakeListNetwork {
  PartialReadNetwork(super.dht, {required this.firstNetworkReadMembers});

  /// members visible to the first network read; later reads see them all.
  final Set<int> firstNetworkReadMembers;
  int _networkReads = 0;

  @override
  Future<DocsRead> readDocs(
    String recordKey,
    int memberCount, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      // nothing cached on this device, and a local read is never the whole
      // picture anyway.
      return (docs: const <int, String>{}, complete: false);
    }
    final all = await super.readDocs(
      recordKey,
      memberCount,
      forceRefresh: forceRefresh,
    );
    if (_networkReads++ > 0) return all;
    return (
      docs: {
        for (final e in all.docs.entries)
          if (firstNetworkReadMembers.contains(e.key)) e.key: e.value,
      },
      complete: false,
    );
  }
}

OpenList openAs(
  FakeDht dht,
  CreatedRecord rec, {
  required int member,
  ListNetwork? net,
}) => OpenList(
  local: LocalList(
    recordKey: rec.recordKey,
    isOwner: false,
    writer: rec.pool[member],
    memberIndex: member,
    title: '',
    addedAt: 0,
  ),
  network: net ?? FakeListNetwork(dht),
);

void writeMember(FakeDht dht, String key, int index, Contribution c) =>
    dht.writeDoc(key, index, jsonEncode(MemberDoc(contribution: c).toJson()));

void main() {
  test('a member reorder converges for another reader', () async {
    final dht = FakeDht();
    final rec = dht.createRecord();
    // member 0 created a, b, c.
    writeMember(
      dht,
      rec.recordKey,
      0,
      Contribution()
        ..addItem('a', 'a', const LogicalTs(1, 0))
        ..addItem('b', 'b', const LogicalTs(2, 0))
        ..addItem('c', 'c', const LogicalTs(3, 0)),
    );
    // member 1 reordered to c, b, a with a newer ts, so its order wins.
    writeMember(
      dht,
      rec.recordKey,
      1,
      Contribution()
        ..setOrder('c', 0, const LogicalTs(10, 1))
        ..setOrder('b', 1, const LogicalTs(10, 1))
        ..setOrder('a', 2, const LogicalTs(10, 1)),
    );

    final open = openAs(dht, rec, member: 2);
    await open.open();
    await settle();
    expect(open.items.map((i) => i.text), ['c', 'b', 'a']);
    open.dispose();
  });

  test(
    'a peer change made while we were closed appears once the node is ready',
    () async {
      final dht = FakeDht();
      final rec = dht.createRecord();
      // a peer wrote an item while this client was not around.
      writeMember(
        dht,
        rec.recordKey,
        1,
        Contribution()..addItem('i1', 'from peer', const LogicalTs(5, 1)),
      );

      // we reopen on a node that is still attaching (not ready yet).
      final net = LatentNetwork(dht)..setReady(false);
      final open = openAs(dht, rec, member: 2, net: net);
      await open.open();
      await settle();
      expect(open.items, isEmpty, reason: 'nothing reachable while attaching');

      // the node finishes attaching; the missed change must now sync in.
      net.setReady(true);
      await settle();
      await settle();

      expect(
        open.items.map((i) => i.text),
        ['from peer'],
        reason: 'becoming ready must resync changes missed while closed',
      );
      open.dispose();
    },
  );

  test('a partial first read must not be reported as fully synced', () {
    // reported after joining by scanning a qr code: the list appears, the chip
    // shows "synced", and then the list keeps rewriting itself for a while. a
    // joiner's first read can return only some members' subkeys, and OpenList
    // marks the list live-synced after ANY read that completes while the node is
    // ready - so the chip claims everything has arrived while the remaining
    // members' docs are still landing, each one visibly re-folding the list.
    fakeAsync((async) {
      final dht = FakeDht();
      final rec = dht.createRecord();
      writeMember(
        dht,
        rec.recordKey,
        0,
        Contribution()..addItem('a', 'from member 0', const LogicalTs(1, 0)),
      );
      writeMember(
        dht,
        rec.recordKey,
        1,
        Contribution()..addItem('b', 'from member 1', const LogicalTs(2, 1)),
      );

      // the joiner's first network read only reaches member 0's subkey.
      final net = PartialReadNetwork(dht, firstNetworkReadMembers: {0});
      final open = openAs(dht, rec, member: 2, net: net);
      unawaited(open.open());
      async.flushMicrotasks();

      expect(
        open.items.map((i) => i.text),
        ['from member 0'],
        reason: 'only part of the record has been read so far',
      );
      expect(
        open.syncStatus,
        isNot(SyncStatus.synced),
        reason: 'the chip must not claim synced while the view is incomplete',
      );
      expect(
        open.awaitingInitialSync,
        isTrue,
        reason:
            'a first-ever join keeps its spinner until the list is whole, '
            'rather than showing a fragment that then rewrites itself',
      );

      // once the rest arrives the view is whole, and only then is it synced.
      async.elapse(const Duration(seconds: 15));
      expect(open.items.map((i) => i.text), ['from member 0', 'from member 1']);
      expect(open.syncStatus, SyncStatus.synced);
      expect(open.awaitingInitialSync, isFalse);
      open.dispose();
    });
  });

  test('a live view reconciles a change whose watch update was dropped', () {
    // the watch is the fast path but the network can silently drop a
    // notification (a coalesced value change, or a peer's post-offline flush an
    // online viewer misses). the background reconcile must still pull it in;
    // without it a live view strands an edit behind forever. FakeDht's
    // dropNextChanges injects exactly that lost notification. fakeAsync drives
    // the periodic reconcile timer without real waiting.
    fakeAsync((async) {
      final dht = FakeDht();
      final rec = dht.createRecord();
      // member 0 created item x; the viewer (member 1) opens and live-syncs.
      writeMember(
        dht,
        rec.recordKey,
        0,
        Contribution()..addItem('x', 'hello', const LogicalTs(1, 0)),
      );
      final open = openAs(dht, rec, member: 1);
      unawaited(open.open());
      async.flushMicrotasks();
      expect(open.items.map((i) => i.text), ['hello']);

      // member 0 renames x, but the network loses the watch notification.
      dht.dropNextChanges(1);
      writeMember(
        dht,
        rec.recordKey,
        0,
        Contribution()..addItem('x', 'world', const LogicalTs(2, 0)),
      );
      async.elapse(const Duration(seconds: 2));
      expect(
        open.items.map((i) => i.text),
        ['hello'],
        reason: 'the dropped notification leaves the view momentarily stale',
      );

      // the background reconcile must catch it within a few ticks.
      async.elapse(const Duration(seconds: 15));
      expect(
        open.items.map((i) => i.text),
        ['world'],
        reason: 'reconcile pulls in a change the watch dropped',
      );
      open.dispose();
    });
  });
}

// sync behaviour of a single OpenList: cross-member ordering converges, and a
// change a peer made while this client was closed must appear once the node
// finishes attaching. the second test reproduces the reopen-does-not-resync bug
// (a reorder synced peer-to-peer but not to a client that was closed at the
// time and cold-starts on reopen).

import 'dart:convert';

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
  Future<Map<int, String>> readDocs(
    String recordKey,
    int memberCount, {
    bool forceRefresh = false,
  }) async => isReady
      ? super.readDocs(recordKey, memberCount, forceRefresh: forceRefresh)
      : <int, String>{};
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
}

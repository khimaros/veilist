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
import 'package:veilist/models/item_state.dart';

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

// a fake network that hands back a STALE copy of a member's doc, the way a dht
// read can: getDHTValue fans out to whichever nodes answer, and a replica that
// has not caught up returns an earlier version of the subkey.
class StaleReplicaNetwork extends FakeListNetwork {
  StaleReplicaNetwork(super.dht);

  /// docs to serve instead of the dht's current ones, until cleared.
  Map<int, String>? staleDocs;

  @override
  Future<DocsRead> readDocs(
    String recordKey,
    int memberCount, {
    bool forceRefresh = false,
  }) async {
    final stale = staleDocs;
    if (stale == null) {
      return super.readDocs(recordKey, memberCount, forceRefresh: forceRefresh);
    }
    return (docs: Map.of(stale), complete: true);
  }
}

// a fake network that models veilid's sequence numbers. a write is stamped with
// the sequence of the value the writer held when the write STARTED, and the dht
// keeps the FIRST value it receives at a given sequence: a later write stamped
// with the same sequence is discarded however much newer its contents, and the
// writer is told nothing. two overlapping writes to one subkey therefore lose
// one of them silently - which is what veilid does in production (a node's log
// shows three docs going out at seq=1 and only the first surviving).
class SeqCollidingNetwork extends FakeListNetwork {
  SeqCollidingNetwork(super.dht);

  final Map<String, int> _committed = {};

  /// writes the dht threw away because they collided with an earlier one.
  int dropped = 0;

  @override
  Future<void> writeDoc(String recordKey, int memberIndex, String json) async {
    final slot = '$recordKey/$memberIndex';
    final stamped = (_committed[slot] ?? 0) + 1;
    // the fanout takes long enough for another edit's write to start.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (stamped <= (_committed[slot] ?? 0)) {
      dropped++;
      return;
    }
    _committed[slot] = stamped;
    return super.writeDoc(recordKey, memberIndex, json);
  }
}

// records the order of writes and closes, so a test can catch a write issued
// after the record was released - veilid rejects that outright, and the edit is
// gone with nothing left to retry it.
class OrderRecordingNetwork extends FakeListNetwork {
  OrderRecordingNetwork(super.dht);

  final List<String> events = [];

  @override
  Future<void> writeDoc(String recordKey, int memberIndex, String json) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    events.add('write');
    return super.writeDoc(recordKey, memberIndex, json);
  }

  @override
  Future<void> closeRecord(String recordKey) async => events.add('close');
}

OpenList openAs(
  FakeDht dht,
  CreatedRecord rec, {
  required int member,
  ListNetwork? net,
  HybridClock? clock,
}) => OpenList(
  clock: clock,
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
  test('edits made in quick succession all reach the dht', () async {
    // three taps in a row: each ui handler starts its own write without waiting
    // for the previous one, so the writes overlap. they all carry the whole
    // member doc, so the last one is a superset of the others - but the dht
    // stamps each with the sequence it saw when it started, keeps the first,
    // and silently drops the rest. the peer then never sees the later edits
    // while this device shows them and reports "synced".
    final dht = FakeDht();
    final rec = dht.createRecord();
    final net = SeqCollidingNetwork(dht);
    final open = openAs(dht, rec, member: 0, net: net);
    await open.open();
    await settle();

    await Future.wait([
      open.addItem('one'),
      open.addItem('two'),
      open.addItem('three'),
    ]);
    await settle();

    final stored = MemberDoc.fromJson(
      jsonDecode(dht.readDocs(rec.recordKey)[0]!) as Map<String, dynamic>,
    );
    expect(
      foldDocs([stored]).items.map((i) => i.text),
      containsAll(['one', 'two', 'three']),
    );
    expect(net.dropped, 0, reason: 'a write was discarded by the dht');
    open.dispose();
  });

  test('an edit made during a write goes out before the record closes', () async {
    // edit, then straight back to the listing - ordinary use. the second edit is
    // queued behind the first write, and closing the record before it goes out
    // would lose it: a write to a closed record fails outright.
    final dht = FakeDht();
    final rec = dht.createRecord();
    final net = OrderRecordingNetwork(dht);
    final open = openAs(dht, rec, member: 0, net: net);
    await open.open();
    await settle();

    unawaited(open.addItem('one'));
    unawaited(open.addItem('two'));
    open.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(net.events, ['write', 'write', 'close']);
    final stored = MemberDoc.fromJson(
      jsonDecode(dht.readDocs(rec.recordKey)[0]!) as Map<String, dynamic>,
    );
    expect(
      foldDocs([stored]).items.map((i) => i.text),
      containsAll(['one', 'two']),
    );
  });

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

  test('a stale read of a member must not move the view backwards', () {
    // reported as the list "bouncing" between states. the crdt resolves per
    // field by greatest ts, but OpenList REPLACES a member's whole doc on every
    // read, so an older copy from a lagging dht replica regresses that member's
    // contribution and the fold visibly steps back - then the next read moves it
    // forward again. a member's doc must be merged into what we already hold, so
    // the view can only ever move forward.
    fakeAsync((async) {
      final dht = FakeDht();
      final rec = dht.createRecord();
      // the older copy: item x is still new.
      final stale = jsonEncode(
        MemberDoc(
          contribution: Contribution()
            ..addItem('x', 'wash dishes', const LogicalTs(5, 0)),
        ).toJson(),
      );
      // the current copy: member 0 has since completed it.
      writeMember(
        dht,
        rec.recordKey,
        0,
        Contribution()
          ..addItem('x', 'wash dishes', const LogicalTs(5, 0))
          ..setState('x', ItemState.complete, const LogicalTs(10, 0)),
      );

      final net = StaleReplicaNetwork(dht);
      final open = openAs(dht, rec, member: 1, net: net);
      unawaited(open.open());
      async.flushMicrotasks();
      expect(open.items.single.state, ItemState.complete);

      // a later read lands on a replica that has not caught up.
      net.staleDocs = {0: stale};
      async.elapse(const Duration(seconds: 15));
      expect(
        open.items.single.state,
        ItemState.complete,
        reason:
            'a stale read must not un-complete an item the view already has',
      );
      open.dispose();
    });
  });

  test('a device with a slow clock still wins after seeing a peer', () async {
    // the reason ordering does not hang on the devices' clocks agreeing: this
    // device's wall clock is an hour behind its peer's, but it has READ the
    // peer's edit before making its own, so its edit is causally later and must
    // win. with plain wall-clock last-writer-wins the peer's older edit would
    // outrank it and the user's change would silently vanish.
    final dht = FakeDht();
    final rec = dht.createRecord();
    const anHour = 3600 * 1000000;

    // the peer (member 0) completes an item, stamped from a clock an hour fast.
    writeMember(
      dht,
      rec.recordKey,
      0,
      Contribution()
        ..addItem('x', 'wash dishes', const LogicalTs(anHour, 0))
        ..setState('x', ItemState.complete, const LogicalTs(anHour, 0)),
    );

    // we open on a device whose clock reads 1000 microseconds past the epoch.
    final open = openAs(
      dht,
      rec,
      member: 1,
      clock: HybridClock(physicalNow: () => 1000),
    );
    await open.open();
    await settle();
    expect(open.items.single.state, ItemState.complete);

    // having seen it, we re-open the item.
    await open.setItemState(open.items.single.id, ItemState.unstarted);
    await settle();
    expect(
      open.items.single.state,
      ItemState.unstarted,
      reason: 'our later edit must outrank the peer despite the slower clock',
    );

    // and a third party folding both members' docs agrees.
    final other = openAs(dht, rec, member: 2);
    await other.open();
    await settle();
    expect(other.items.single.state, ItemState.unstarted);
    open.dispose();
    other.dispose();
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

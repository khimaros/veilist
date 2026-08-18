import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:veilist/data/list_network.dart';
import 'package:veilist/data/list_repository.dart';
import 'package:veilist/data/list_store.dart';
import 'package:veilist/models/item_state.dart';

import '../fakes/fake_backend.dart';

ListRepository make(FakeDht dht, {ListStore? store}) => ListRepository(
  store: store ?? FakeListStore(),
  network: FakeListNetwork(dht),
);

// records which subkey each write went to, so a test can see the repository
// refresh a record rather than only read it.
class WriteRecordingNetwork extends FakeListNetwork {
  WriteRecordingNetwork(super.dht);

  final List<({String key, int member})> writes = [];

  @override
  Future<void> writeDoc(String recordKey, int memberIndex, String json) {
    writes.add((key: recordKey, member: memberIndex));
    return super.writeDoc(recordKey, memberIndex, json);
  }
}

// counts opens and reads per record, and holds each open until released, so a
// test can see how many records the foreground sync has in flight at once and
// what a change arriving mid-sync does.
class GatedOpenNetwork extends FakeListNetwork {
  GatedOpenNetwork(super.dht);

  final Map<String, int> opens = {};
  final Map<String, int> reads = {};
  Completer<void>? gate;

  @override
  Future<int> openRecord(String recordKey, {required String writer}) async {
    opens.update(recordKey, (n) => n + 1, ifAbsent: () => 1);
    await gate?.future;
    return super.openRecord(recordKey, writer: writer);
  }

  @override
  Future<DocsRead> readDocs(
    String recordKey,
    int memberCount, {
    bool forceRefresh = false,
  }) {
    reads.update(recordKey, (n) => n + 1, ifAbsent: () => 1);
    return super.readDocs(recordKey, memberCount, forceRefresh: forceRefresh);
  }
}

// let broadcast change events flush to watchers.
Future<void> settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('create adds an owned list to the roster', () async {
    final repo = make(FakeDht());
    await repo.load();
    final list = await repo.createList('groceries');
    expect(repo.lists.length, 1);
    expect(list.isOwner, isTrue);
    expect(list.title, 'groceries');
    expect(list.memberIndex, 0);
  });

  test('a saved roster reloads across a restart', () async {
    final dht = FakeDht();
    final store = FakeListStore();
    final first = make(dht, store: store);
    await first.load();
    await first.createList('persists');

    final restarted = make(dht, store: store);
    await restarted.load();
    expect(restarted.lists.single.title, 'persists');
  });

  test('delete removes the list from the roster and store', () async {
    final dht = FakeDht();
    final store = FakeListStore();
    final repo = make(dht, store: store);
    await repo.load();
    final list = await repo.createList('temp');
    await repo.deleteList(list);
    expect(repo.lists, isEmpty);

    final reloaded = make(dht, store: store);
    await reloaded.load();
    expect(reloaded.lists, isEmpty);
  });

  test('sharing allocates a distinct member slot per invite', () async {
    final repo = make(FakeDht());
    await repo.load();
    final list = await repo.createList('party');
    final a = await repo.shareList(list);
    final b = await repo.shareList(list);
    expect(a.memberIndex, isNot(list.memberIndex));
    expect(a.memberIndex, isNot(b.memberIndex)); // each invite is attributable
  });

  test('alice shares, bob joins, and edits converge both ways', () async {
    final dht = FakeDht();
    final alice = make(dht);
    final bob = make(dht);
    await alice.load();
    await bob.load();

    final aliceList = await alice.createList('trip');
    final link = await alice.shareList(aliceList);
    final bobList = await bob.joinList(link);
    expect(bobList.title, 'trip'); // bob sees the shared title
    expect(bobList.memberIndex, isNot(aliceList.memberIndex));

    final aliceOpen = alice.open(aliceList);
    final bobOpen = bob.open(bobList);
    await aliceOpen.open();
    await bobOpen.open();

    // alice adds an item; bob receives it over the (fake) watch.
    await aliceOpen.addItem('pack bags');
    await settle();
    expect(bobOpen.items.map((i) => i.text), contains('pack bags'));

    // bob ticks the item off; alice sees the change.
    await bobOpen.toggleState(bobOpen.items.first.id);
    await settle();
    expect(aliceOpen.items.single.state, ItemState.complete);

    // both actors converged to the same single item in the same state.
    expect(aliceOpen.items.length, bobOpen.items.length);
    expect(bobOpen.items.single.state, ItemState.complete);

    aliceOpen.dispose();
    bobOpen.dispose();
  });

  test('a later editor wins on a shared field (last-writer-wins)', () async {
    final dht = FakeDht();
    final alice = make(dht);
    final bob = make(dht);
    await alice.load();
    await bob.load();
    final list = await alice.createList('notes');
    final bobList = await bob.joinList(await alice.shareList(list));

    final a = alice.open(list);
    final b = bob.open(bobList);
    await a.open();
    await b.open();

    await a.addItem('draft');
    await settle();
    final id = b.items.single.id;

    // bob renames after alice; bob's text wins for everyone.
    await a.setText(id, 'alice version');
    await settle();
    await b.setText(id, 'bob version');
    await settle();
    expect(a.items.single.text, 'bob version');
    expect(b.items.single.text, 'bob version');

    a.dispose();
    b.dispose();
  });

  // two members editing while apart (offline) must merge non-destructively when
  // they reconnect: every non-conflicting change has to survive.
  test(
    'items added by two members while apart all survive the merge',
    () async {
      final dht = FakeDht();
      final alice = make(dht);
      final bob = make(dht);
      await alice.load();
      await bob.load();
      final list = await alice.createList('trip');
      final bobList = await bob.joinList(await alice.shareList(list));
      final a = alice.open(list);
      final b = bob.open(bobList);
      await a.open();
      await b.open();

      // each adds an item without seeing the other's write first.
      await a.addItem('passport');
      await b.addItem('sunscreen');
      await settle();

      // neither add is lost: both members converge on both items.
      expect(
        a.items.map((i) => i.text),
        containsAll(['passport', 'sunscreen']),
      );
      expect(
        b.items.map((i) => i.text),
        containsAll(['passport', 'sunscreen']),
      );
      expect(a.items.length, 2);
      expect(b.items.length, 2);

      a.dispose();
      b.dispose();
    },
  );

  test(
    'concurrent edits to different fields of one item both survive',
    () async {
      final dht = FakeDht();
      final alice = make(dht);
      final bob = make(dht);
      await alice.load();
      await bob.load();
      final list = await alice.createList('trip');
      final bobList = await bob.joinList(await alice.shareList(list));
      final a = alice.open(list);
      final b = bob.open(bobList);
      await a.open();
      await b.open();
      await a.addItem('bags');
      await settle();
      final id = b.items.single.id;

      // alice renames the item while bob marks it blocked from the state
      // picker, independently.
      await a.setText(id, 'carry-on');
      await b.setItemState(id, ItemState.blocked);
      await settle();

      // per-field last-writer-wins: alice's text and bob's state each win their
      // own field, so neither edit clobbers the other.
      for (final open in [a, b]) {
        final item = open.items.single;
        expect(item.text, 'carry-on');
        expect(item.state, ItemState.blocked);
      }

      a.dispose();
      b.dispose();
    },
  );

  // foreground sync keeps the whole roster current: a peer's change to a list
  // reaches this device even though it never opened that list's detail page.
  test('foreground sync updates the roster without opening the list', () async {
    final dht = FakeDht();
    final alice = make(dht);
    final bob = make(dht);
    await alice.load();
    await bob.load();

    final list = await alice.createList('old name');
    await bob.joinList(await alice.shareList(list));
    expect(bob.lists.single.title, 'old name');

    await bob.startForegroundSync();

    // alice renames; bob must reflect it without opening the list.
    final a = alice.open(list);
    await a.open();
    await settle();
    await a.setTitle('new name');
    await settle();
    await settle();

    expect(bob.lists.single.title, 'new name');

    a.dispose();
    await bob.stopForegroundSync();
  });

  test(
    'a created list is local until shared: instant, editable, no dht',
    () async {
      final dht = FakeDht();
      final repo = make(dht);
      await repo.load();
      final list = await repo.createList('secret');
      // local-only: a placeholder key and nothing published.
      expect(list.published, isFalse);
      expect(list.recordKey.startsWith('local:'), isTrue);
      // editable immediately, with no network involved.
      final open = repo.open(list);
      await open.open();
      await settle();
      await open.addItem('buy milk');
      await settle();
      expect(open.items.map((i) => i.text), ['buy milk']);
      open.dispose();
      // the local edit persists across a reopen.
      final reopened = repo.open(list);
      await reopened.open();
      await settle();
      expect(reopened.items.map((i) => i.text), ['buy milk']);
      reopened.dispose();
    },
  );

  test(
    'sharing publishes a local list; a joiner sees pre-share items',
    () async {
      final dht = FakeDht();
      final repo = make(dht);
      await repo.load();
      final list = await repo.createList('trip');
      final o = repo.open(list);
      await o.open();
      await o.addItem('pack bags');
      await settle();
      o.dispose();

      final link = await repo.shareList(list);
      // now published under a real record, not a local placeholder.
      expect(list.published, isTrue);
      expect(list.recordKey.startsWith('local:'), isFalse);

      // a joiner reads the items that existed before the share.
      final bob = make(dht);
      await bob.load();
      final bobList = await bob.joinList(link);
      final bobOpen = bob.open(bobList);
      await bobOpen.open();
      await settle();
      expect(bobOpen.items.map((i) => i.text), contains('pack bags'));
      bobOpen.dispose();
    },
  );

  test('foreground sync republishes a record nothing has written to', () async {
    // veilid's storage nodes hold other people's records under an lru, so a
    // record nobody writes to is eventually evicted from every node holding it
    // and the members can no longer reach each other. re-writing this device's
    // own doc is what keeps it there.
    final dht = FakeDht();
    final net = WriteRecordingNetwork(dht);
    final repo = ListRepository(store: FakeListStore(), network: net);
    await repo.load();
    final list = await repo.shareList(await repo.createList('groceries'));
    final published = repo.lists.single;
    net.writes.clear();

    published.republishedAt = 0; // nothing has written to it since
    await repo.startForegroundSync();
    await settle();
    expect(net.writes, [(key: list.recordKey, member: 0)]);

    // and not on every sync: only once the interval has passed again.
    net.writes.clear();
    await repo.stopForegroundSync();
    await repo.startForegroundSync();
    await settle();
    expect(net.writes, isEmpty);
    await repo.stopForegroundSync();
  });

  // the roster's watches are rebuilt on every resume from background, so
  // opening them one at a time put the last list a full round trip behind every
  // earlier one. and syncing them at once must still open each record once:
  // VeilidListNetwork refcounts opens, so a double open leaves a ref behind
  // that the single close on background never releases.
  test('foreground sync opens the roster at once, each record once', () async {
    final dht = FakeDht();
    final net = GatedOpenNetwork(dht);
    final repo = ListRepository(store: FakeListStore(), network: net);
    await repo.load();
    final a = await repo.shareList(await repo.createList('a'));
    final b = await repo.shareList(await repo.createList('b'));
    await repo.shareList(await repo.createList('c'));

    net.opens.clear(); // publishing opened each record once already
    net.reads.clear();
    net.gate = Completer<void>();
    unawaited(repo.startForegroundSync());
    await settle();
    // all three are open at once, not one waiting on the last to finish.
    expect(net.opens.length, 3);

    // a watch update for a record whose sync is still in flight must not start
    // a second one: nothing has reached _watched yet, so only an in-flight
    // guard stops it opening the record again.
    dht.writeDoc(a.recordKey, 4, '{"i":{}}');
    await settle();
    net.gate!.complete();
    await settle();
    expect(net.opens[a.recordKey], 1);

    // but it must not be dropped either. that read started before the write
    // landed, and a watch fires once per change, so nothing else is coming: the
    // record has to be read again once the in-flight sync finishes.
    expect(net.reads[a.recordKey], 2);
    expect(net.reads[b.recordKey], 1);

    await repo.stopForegroundSync();
  });

  // create/join/share re-key or another readiness-triggered sync mutating the
  // roster mid-iteration must not throw "concurrent modification".
  test('roster mutation during a foreground sync does not crash', () async {
    final dht = FakeDht();
    final net = FakeListNetwork(dht);
    final repo = ListRepository(store: FakeListStore(), network: net);
    await repo.load();
    await repo.shareList(await repo.createList('a')); // publish
    await repo.shareList(await repo.createList('b')); // publish
    await repo.startForegroundSync();

    // a readiness change re-runs _syncAll; mutate the roster while it is in
    // flight. an unhandled concurrent-modification error would fail the test.
    net.setReady(false);
    net.setReady(true);
    await repo.createList('c');
    await repo.createList('d');
    await settle();
    await settle();

    await repo.stopForegroundSync();
    expect(repo.lists.length, 4);
  });

  test(
    'renameList updates the cached title (open-time refresh must not clobber '
    'the in-flight edit)',
    () async {
      final repo = make(FakeDht());
      await repo.load();
      final list = await repo.createList('old');
      await repo.renameList(list, 'new');
      expect(list.title, 'new');
      expect(repo.lists.single.title, 'new');
    },
  );

  test('any member can rename a shared list; the latest rename wins', () async {
    final dht = FakeDht();
    final alice = make(dht);
    final bob = make(dht);
    await alice.load();
    await bob.load();
    final list = await alice.createList('draft');
    final bobList = await bob.joinList(await alice.shareList(list));

    final a = alice.open(list);
    final b = bob.open(bobList);
    await a.open();
    await b.open();
    await settle();

    // bob (a member, not the owner) renames; alice converges to it.
    await b.setTitle('final');
    await settle();
    expect(a.title, 'final');
    expect(b.title, 'final');

    a.dispose();
    b.dispose();
  });

  // R17: the listing shows only a title, so without a mark a peer's edits are
  // invisible until you open the list and compare against memory.
  test("a peer's edit marks the list as updated in the roster", () async {
    final dht = FakeDht();
    final alice = make(dht);
    final bob = make(dht);
    await alice.load();
    await bob.load();

    final list = await alice.createList('trip');
    final bobList = await bob.joinList(await alice.shareList(list));
    // joining is deliberate and the joiner opens the list next, so what came
    // with the invitation is not an unseen change.
    expect(bobList.hasUpdates, isFalse);

    await bob.startForegroundSync();
    final a = alice.open(list);
    await a.open();
    await a.addItem('passport');
    await settle();
    await settle();
    expect(bob.lists.single.hasUpdates, isTrue);

    // looking at it clears the mark, and a later peer edit sets it again.
    final b = bob.open(bobList);
    await b.open();
    await settle();
    bob.markSeen(bobList, b.digest);
    expect(bobList.hasUpdates, isFalse);
    b.dispose();

    await a.addItem('sunscreen');
    await settle();
    await settle();
    expect(bob.lists.single.hasUpdates, isTrue);

    a.dispose();
    await bob.stopForegroundSync();
  });

  // a list you made and have been editing yourself is not news to you.
  test('your own list is never marked updated by syncing it', () async {
    final dht = FakeDht();
    final repo = make(dht);
    await repo.load();
    final list = await repo.createList('mine');
    await repo.shareList(list);

    final open = repo.open(list);
    await open.open();
    await open.addItem('a thing');
    await settle();
    repo.markSeen(list, open.digest);
    open.dispose();

    await repo.startForegroundSync();
    await settle();
    await settle();
    expect(list.hasUpdates, isFalse);
    await repo.stopForegroundSync();
  });

  // the listing already renders the title, so a rename needs no mark - and
  // counting it would make your own rename from the listing come straight back
  // at you as somebody else's change.
  test('renaming your own list does not mark it updated', () async {
    final repo = make(FakeDht());
    await repo.load();
    final list = await repo.createList('old');
    await repo.shareList(list);
    await repo.startForegroundSync();
    await settle();

    await repo.renameList(list, 'new');
    await settle();
    await settle();
    expect(list.title, 'new');
    expect(list.hasUpdates, isFalse);
    await repo.stopForegroundSync();
  });

  test('an updated mark survives a restart', () async {
    final dht = FakeDht();
    final store = FakeListStore();
    final alice = make(dht);
    final bob = ListRepository(store: store, network: FakeListNetwork(dht));
    await alice.load();
    await bob.load();
    final list = await alice.createList('trip');
    final bobList = await bob.joinList(await alice.shareList(list));

    await bob.startForegroundSync();
    final a = alice.open(list);
    await a.open();
    await a.addItem('passport');
    await settle();
    await settle();
    expect(bobList.hasUpdates, isTrue);
    a.dispose();
    await bob.stopForegroundSync();

    // the mark is about what this device has looked at, so closing the app
    // must not count as having looked.
    final restarted = ListRepository(
      store: store,
      network: FakeListNetwork(dht),
    );
    await restarted.load();
    expect(restarted.lists.single.hasUpdates, isTrue);
  });
}

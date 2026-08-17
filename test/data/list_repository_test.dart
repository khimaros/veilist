import 'package:flutter_test/flutter_test.dart';
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

  // the foreground sync iterates the roster with awaits between entries; a
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
}

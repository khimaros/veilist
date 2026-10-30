import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veilist/data/list_network.dart';
import 'package:veilist/data/list_repository.dart';
import 'package:veilist/ui/list_detail_page.dart';

import '../fakes/fake_backend.dart';

class _HoldReadNetwork extends FakeListNetwork {
  _HoldReadNetwork(super.dht);

  final Completer<void> forcedReadGate = Completer<void>();
  ReadProgressCallback? lastProgress;

  @override
  Future<DocsRead> readDocs(
    String recordKey,
    int memberCount, {
    bool forceRefresh = false,
    ReadProgressCallback? onProgress,
  }) async {
    if (!forceRefresh) return (docs: const <int, String>{}, complete: false);
    lastProgress = onProgress;
    await forcedReadGate.future;
    return super.readDocs(recordKey, memberCount, forceRefresh: true);
  }
}

class _FailOpenNetwork extends FakeListNetwork {
  _FailOpenNetwork(super.dht);

  @override
  Future<int> openRecord(String recordKey, {required String writer}) async =>
      throw StateError('KeyNotFound');
}

void main() {
  testWidgets('add an item, then toggle it complete via the checkbox', (
    tester,
  ) async {
    final repo = ListRepository(
      store: FakeListStore(),
      network: FakeListNetwork(FakeDht()),
    );
    await repo.load();
    final list = await repo.createList('chores');

    await tester.pumpWidget(
      MaterialApp(
        home: ListDetailPage(repository: repo, local: list),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('no items yet - add one below'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'buy milk');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('buy milk'), findsOneWidget);

    // the checkbox starts on `new` (blank glyph); a tap completes the item and
    // a second tap re-opens it.
    expect(find.byType(StateGlyphButton), findsOneWidget);
    await tester.tap(find.byType(StateGlyphButton));
    await tester.pumpAndSettle();
    expect(find.text('x'), findsOneWidget); // complete glyph
    await tester.tap(find.byType(StateGlyphButton));
    await tester.pumpAndSettle();
    expect(find.text('x'), findsNothing);
  });

  testWidgets('press and hold the checkbox to pick another state', (
    tester,
  ) async {
    final repo = ListRepository(
      store: FakeListStore(),
      network: FakeListNetwork(FakeDht()),
    );
    await repo.load();
    final list = await repo.createList('chores');

    await tester.pumpWidget(
      MaterialApp(
        home: ListDetailPage(repository: repo, local: list),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('add_field')), 'call plumber');
    await tester.tap(find.byKey(const Key('add_button')));
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(StateGlyphButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('state_picker')), findsOneWidget);

    await tester.tap(find.byKey(const Key('state_blocked')));
    await tester.pumpAndSettle();
    expect(find.text('!'), findsOneWidget); // blocked glyph
  });

  testWidgets('holding anywhere on the row opens the state picker', (
    tester,
  ) async {
    // the checkbox is a small target to find by touch, so the whole row carries
    // the same press-and-hold.
    final repo = ListRepository(
      store: FakeListStore(),
      network: FakeListNetwork(FakeDht()),
    );
    await repo.load();
    final list = await repo.createList('chores');

    await tester.pumpWidget(
      MaterialApp(
        home: ListDetailPage(repository: repo, local: list),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('add_field')), 'call plumber');
    await tester.tap(find.byKey(const Key('add_button')));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('call plumber'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('state_picker')), findsOneWidget);

    await tester.tap(find.byKey(const Key('state_active')));
    await tester.pumpAndSettle();
    expect(find.text('@'), findsOneWidget); // active glyph
  });

  testWidgets('adding an item scrolls the list down to show it', (
    tester,
  ) async {
    final repo = ListRepository(
      store: FakeListStore(),
      network: FakeListNetwork(FakeDht()),
    );
    await repo.load();
    final list = await repo.createList('chores');

    await tester.pumpWidget(
      MaterialApp(
        home: ListDetailPage(repository: repo, local: list),
      ),
    );
    await tester.pumpAndSettle();

    // more items than fit the viewport, so the newest row is only built - and
    // so only findable - if the list followed it down.
    for (var i = 0; i < 20; i++) {
      await tester.enterText(find.byKey(const Key('add_field')), 'item-$i');
      await tester.tap(find.byKey(const Key('add_button')));
      await tester.pumpAndSettle();
    }
    expect(find.text('item-19'), findsOneWidget);
    expect(find.text('item-0'), findsNothing); // scrolled well past the top
  });

  testWidgets('a new item stays in view when the keyboard resizes the list', (
    tester,
  ) async {
    // the keyboard is 200 logical pixels of the 600 the test view has.
    const keyboard = FakeViewPadding(bottom: 600); // physical: dpr is 3
    addTearDown(tester.view.reset);

    final repo = ListRepository(
      store: FakeListStore(),
      network: FakeListNetwork(FakeDht()),
    );
    await repo.load();
    final list = await repo.createList('chores');

    await tester.pumpWidget(
      MaterialApp(
        home: ListDetailPage(repository: repo, local: list),
      ),
    );
    await tester.pumpAndSettle();

    // fill well past the fold with the keyboard already up.
    tester.view.viewInsets = keyboard;
    await tester.pumpAndSettle();
    for (var i = 0; i < 20; i++) {
      await tester.enterText(find.byKey(const Key('add_field')), 'item-$i');
      await tester.tap(find.byKey(const Key('add_button')));
      await tester.pumpAndSettle();
    }
    expect(find.text('item-19'), findsOneWidget);

    // now the moving case: the viewport shrinks AFTER the add has aimed its
    // scroll, which is what happens when the add button takes focus off the
    // field and it is handed straight back - the keyboard slides out and in
    // again, and every frame of that moves the end of the list further down.
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('add_field')), 'item-20');
    await tester.tap(find.byKey(const Key('add_button')));
    await tester.pump();
    tester.view.viewInsets = keyboard;
    await tester.pumpAndSettle();
    expect(find.text('item-20'), findsOneWidget);
  });

  testWidgets('hide/show completed toggles which items are visible', (
    tester,
  ) async {
    final repo = ListRepository(
      store: FakeListStore(),
      network: FakeListNetwork(FakeDht()),
    );
    await repo.load();
    final list = await repo.createList('chores');

    await tester.pumpWidget(
      MaterialApp(
        home: ListDetailPage(repository: repo, local: list),
      ),
    );
    await tester.pumpAndSettle();

    for (final text in ['keep', 'finish']) {
      await tester.enterText(find.byKey(const Key('add_field')), text);
      await tester.tap(find.byKey(const Key('add_button')));
      await tester.pumpAndSettle();
    }
    // complete 'finish' with one checkbox tap.
    await tester.tap(find.byType(StateGlyphButton).last);
    await tester.pumpAndSettle();
    expect(find.text('finish'), findsOneWidget);

    // hiding completed removes it; showing brings it back.
    await tester.tap(find.byKey(const Key('toggle_completed')));
    await tester.pumpAndSettle();
    expect(find.text('finish'), findsNothing);
    expect(find.text('keep'), findsOneWidget);

    await tester.tap(find.byKey(const Key('toggle_completed')));
    await tester.pumpAndSettle();
    expect(find.text('finish'), findsOneWidget);
  });

  testWidgets('a failed lookup keeps the progress view while it retries', (
    tester,
  ) async {
    // the open is retried forever, and a raw exception in place of the list
    // reads as final when a retry is already on its way.
    final dht = FakeDht();
    final alice = ListRepository(
      store: FakeListStore(),
      network: FakeListNetwork(dht),
    );
    await alice.load();
    final link = await alice.shareList(await alice.createList('shared'));

    final bobNet = _FailOpenNetwork(dht);
    final bob = ListRepository(store: FakeListStore(), network: bobNet);
    await bob.load();
    final bobList = await bob.joinList(link);

    await tester.pumpWidget(
      MaterialApp(
        home: ListDetailPage(repository: bob, local: bobList),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('could not open list'), findsNothing);
    expect(find.text('syncing the shared list...'), findsOneWidget);
    expect(find.text('finding shared list...'), findsOneWidget);
  });

  testWidgets('shows sync stage while waiting on initial sync, then clears', (
    tester,
  ) async {
    final dht = FakeDht();
    final alice = ListRepository(
      store: FakeListStore(),
      network: FakeListNetwork(dht),
    );
    final bobNet = _HoldReadNetwork(dht);
    final bob = ListRepository(store: FakeListStore(), network: bobNet);
    await alice.load();
    await bob.load();

    final link = await alice.shareList(await alice.createList('shared'));
    final bobList = await bob.joinList(link);

    await tester.pumpWidget(
      MaterialApp(
        home: ListDetailPage(repository: bob, local: bobList),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('syncing the shared list...'), findsOneWidget);
    expect(find.byKey(const Key('sync_stage')), findsOneWidget);
    expect(find.text('checking member slots...'), findsOneWidget);

    bobNet.lastProgress?.call((
      stage: ReadStage.fetching,
      fetched: 1,
      total: 2,
    ));
    await tester.pump();
    expect(find.text('fetching updates (1 of 2)...'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator).last,
    );
    expect(bar.value, 0.5);

    bobNet.forcedReadGate.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sync_stage')), findsNothing);
    expect(find.text('no items yet - add one below'), findsOneWidget);
  });
}

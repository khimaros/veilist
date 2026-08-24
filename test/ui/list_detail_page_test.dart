import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veilist/data/list_repository.dart';
import 'package:veilist/ui/list_detail_page.dart';

import '../fakes/fake_backend.dart';

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
}

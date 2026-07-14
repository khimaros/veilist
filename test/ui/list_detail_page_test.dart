import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veilist/data/list_repository.dart';
import 'package:veilist/ui/list_detail_page.dart';

import '../fakes/fake_backend.dart';

void main() {
  testWidgets('add an item, then cycle its state via the checkbox', (
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

    // the checkbox starts on `new` (blank glyph); tapping cycles to active.
    expect(find.byType(StateGlyphButton), findsOneWidget);
    await tester.tap(find.byType(StateGlyphButton));
    await tester.pumpAndSettle();
    expect(find.text('@'), findsOneWidget); // active glyph
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
    // complete 'finish' (new -> active -> complete) with two checkbox taps.
    await tester.tap(find.byType(StateGlyphButton).last);
    await tester.pumpAndSettle();
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

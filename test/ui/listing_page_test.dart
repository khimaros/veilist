import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veilist/data/list_repository.dart';
import 'package:veilist/ui/listing_page.dart';

import '../fakes/fake_backend.dart';

ListRepository _repo() =>
    ListRepository(store: FakeListStore(), network: FakeListNetwork(FakeDht()));

void main() {
  testWidgets('shows the empty state, then a created list appears', (
    tester,
  ) async {
    final repo = _repo();
    await repo.load();
    await tester.pumpWidget(MaterialApp(home: ListingPage(repository: repo)));

    expect(find.text('no lists yet'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'groceries');
    await tester.tap(find.widgetWithText(FilledButton, 'create'));
    await tester.pumpAndSettle();

    expect(find.text('no lists yet'), findsNothing);
    expect(find.text('groceries'), findsOneWidget);
  });

  testWidgets('a list can be deleted from the listing', (tester) async {
    final repo = _repo();
    await repo.load();
    await repo.createList('temp');
    await tester.pumpWidget(MaterialApp(home: ListingPage(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('temp'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'delete'));
    await tester.pumpAndSettle();

    expect(find.text('temp'), findsNothing);
    expect(find.text('no lists yet'), findsOneWidget);
  });

  // R17: the listing shows only a title, so a change someone else made is
  // otherwise invisible until you open the list and compare against memory.
  // the pipeline that sets the digests is covered in list_repository_test.dart;
  // this is the tile rendering it and the detail page clearing it.
  testWidgets('a changed list is marked, and viewing it clears the mark', (
    tester,
  ) async {
    final repo = _repo();
    await repo.load();
    final list = await repo.createList('trip');
    // what the roster last read differs from what we last had on screen.
    list.contentDigest = 'someone-elses-edit';

    await tester.pumpWidget(MaterialApp(home: ListingPage(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unread')), findsOneWidget);

    await tester.tap(find.text('trip'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unread')), findsNothing);
    expect(list.hasUpdates, isFalse);
  });
}

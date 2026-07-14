import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:veilist/data/share_link.dart';
import 'package:veilist/ui/listing_page.dart';

void main() {
  testWidgets('share dialog renders a qr code and the link without error', (
    tester,
  ) async {
    // a realistic, long app link (record key + writer keypair).
    const link = ShareLink(
      recordKey:
          'VLD0:Thgn-JgA5S06WMsDTbioQX3_4JGpH50ORCh4zjKNWrM:'
          'Bwvd0_OcZyw-bpMaNt9rolDGiDLRvMZTdhmPsJrqCZQ',
      writer:
          'VLD0:e_8heGhiQ_kSPfpQUKZthEzUF_9fUu5X8xNP11JQP3c:'
          'p2U6R1DFlI8qifcdvqFafR05dxm6-jfqfOhdJFSJbyo',
      memberIndex: 1,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showShareDialog(context, link),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.byKey(const Key('app_link_value')), findsOneWidget);
  });
}

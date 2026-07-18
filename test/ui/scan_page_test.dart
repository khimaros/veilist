import 'package:flutter_test/flutter_test.dart';
import 'package:veilist/data/share_link.dart';
import 'package:veilist/ui/scan_page.dart';

void main() {
  const link = ShareLink(
    recordKey: 'VLD0:aXQtaXMtYS1yZWNvcmQta2V5',
    writer: 'VLD0:cHVibGljLWtleQ:c2VjcmV0LWtleQ',
    memberIndex: 3,
  );

  group('shareLinkFromCode', () {
    test('reads both link forms out of a scanned qr code', () {
      for (final uri in [link.toAppUri(), link.toWebUri()]) {
        final scanned = shareLinkFromCode(uri.toString());
        expect(scanned, isNotNull);
        expect(scanned!.recordKey, link.recordKey);
        expect(scanned.memberIndex, link.memberIndex);
      }
    });

    test('tolerates surrounding whitespace from a scan or a paste', () {
      expect(shareLinkFromCode('  ${link.toAppUri()}\n'), isNotNull);
    });

    test('any other code is not a link, rather than an error', () {
      // the camera sees whatever qr is in frame, so a wifi code or plain text
      // must simply not match and let scanning continue.
      for (final raw in [
        null,
        '',
        '   ',
        'hello',
        'WIFI:S=example;T=WPA;P=hunter2;;',
        'https://example.com/',
        '::::',
      ]) {
        expect(shareLinkFromCode(raw), isNull, reason: '$raw');
      }
    });
  });
}

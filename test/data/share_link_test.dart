import 'package:flutter_test/flutter_test.dart';
import 'package:veilist/data/share_link.dart';

void main() {
  const link = ShareLink(
    recordKey: 'VLD0:aXQtaXMtYS1yZWNvcmQta2V5',
    writer: 'VLD0:cHVibGljLWtleQ:c2VjcmV0LWtleQ',
    memberIndex: 3,
  );

  void expectRoundTrip(Uri uri) {
    final parsed = ShareLink.tryParse(uri);
    expect(parsed, isNotNull);
    expect(parsed!.recordKey, link.recordKey);
    expect(parsed.writer, link.writer);
    expect(parsed.memberIndex, link.memberIndex);
  }

  test('app-scheme link round-trips', () => expectRoundTrip(link.toAppUri()));

  test('web fragment link round-trips', () => expectRoundTrip(link.toWebUri()));

  test('the record key survives url encoding of its colons', () {
    // a VLD0: key contains a colon that must not corrupt the path/fragment.
    expect(link.toAppUri().toString(), contains('veilist://l/'));
    expect(link.toWebUri().toString(), contains('/#/l/'));
  });

  test('non-veilist uris parse to null', () {
    expect(ShareLink.tryParse(Uri.parse('https://example.com/')), isNull);
    expect(ShareLink.tryParse(Uri.parse('mailto:a@b.example')), isNull);
    expect(ShareLink.tryParse(Uri.parse('veilist://other/x')), isNull);
  });

  test('a link missing the writer parses to null', () {
    expect(ShareLink.tryParse(Uri.parse('veilist://l/KEY?m=1')), isNull);
  });
}

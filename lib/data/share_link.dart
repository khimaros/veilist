// share links carry everything a recipient needs to open and edit a list: the
// dht record key, a writer keypair for their own member slot, and that slot's
// index (see DESIGN.md "sharing and links").
//
// two equivalent forms are produced. the app form uses a custom scheme so the
// os can hand the link to the app. the web form keeps the payload in the url
// *fragment* so it never reaches the static web host - the browser resolves it
// client-side.

/// custom scheme the app registers for.
const String kAppScheme = 'veilist';

/// path marker identifying a list link, e.g. `veilist://l/<key>`.
const String kLinkSegment = 'l';

/// query keys: writer keypair and member slot index.
const String _qWriter = 'w';
const String _qMember = 'm';

/// production web-fallback base url. the payload rides in the url fragment, so
/// any host serving the web build resolves it client-side. http (not https):
/// veilid's wasm client dials bootstrap nodes over ws://, and an https page
/// cannot open insecure ws:// connections (mixed content).
const String kWebBaseUrl = 'http://veilid.tech/list';

class ShareLink {
  const ShareLink({
    required this.recordKey,
    required this.writer,
    required this.memberIndex,
  });

  /// the dht record key (a VLD0: typed key string).
  final String recordKey;

  /// the recipient's writer keypair (VLD0:pub:secret) for their member slot.
  final String writer;

  /// which pre-allocated member slot this writer occupies.
  final int memberIndex;

  Map<String, String> get _query => {
    _qWriter: writer,
    _qMember: '$memberIndex',
  };

  /// `veilist://l/<recordKey>?w=<writer>&m=<index>`
  Uri toAppUri() => Uri(
    scheme: kAppScheme,
    host: kLinkSegment,
    pathSegments: [recordKey],
    queryParameters: _query,
  );

  /// `<base>/#/l/<recordKey>?w=<writer>&m=<index>`. the payload sits in the
  /// fragment; each component is encoded exactly once so a single
  /// [Uri.fragment] decode on parse recovers it.
  Uri toWebUri([String base = kWebBaseUrl]) {
    final rk = Uri.encodeComponent(recordKey);
    final w = Uri.encodeComponent(writer);
    return Uri.parse(
      '$base/#/$kLinkSegment/$rk?$_qWriter=$w&$_qMember=$memberIndex',
    );
  }

  /// parse either form. returns null if [uri] is not a well-formed list link.
  static ShareLink? tryParse(Uri uri) {
    if (uri.scheme == kAppScheme) {
      // app form: the marker is the host, the key is the path.
      if (uri.host != kLinkSegment || uri.pathSegments.isEmpty) return null;
      return _build(uri.pathSegments.last, uri.queryParameters);
    }
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      // web form: the payload lives in the fragment as `/l/<key>?w=..&m=..`.
      if (uri.fragment.isEmpty) return null;
      final inner = Uri.tryParse(uri.fragment);
      if (inner == null) return null;
      final segs = inner.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segs.length < 2 || segs.first != kLinkSegment) return null;
      return _build(segs.last, inner.queryParameters);
    }
    return null;
  }

  static ShareLink? _build(String recordKey, Map<String, String> q) {
    final writer = q[_qWriter];
    final member = int.tryParse(q[_qMember] ?? '');
    if (recordKey.isEmpty ||
        writer == null ||
        writer.isEmpty ||
        member == null) {
      return null;
    }
    return ShareLink(recordKey: recordKey, writer: writer, memberIndex: member);
  }
}

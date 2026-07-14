// on web, observe url hash changes so a share link pasted into an already-open
// tab opens the list. a no-op everywhere else.
export 'web_url_stub.dart' if (dart.library.js_interop) 'web_url_web.dart';

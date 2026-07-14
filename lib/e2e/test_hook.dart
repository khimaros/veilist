// installs a small window.veilistTest surface so the browser e2e can drive real
// list operations over the live dht (flutter's canvas ui cannot be driven from
// the dom). only wired up when built with --dart-define=VEILIST_E2E=true, so it
// never ships in a normal build. no-op off the web.
export 'test_hook_stub.dart' if (dart.library.js_interop) 'test_hook_web.dart';

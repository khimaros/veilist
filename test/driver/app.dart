// e2e entrypoint for the flutter-driver ui tests (appium on android, the dart vm
// service on linux; see test/e2e/). exposes flutter's driver extension so an
// external test can find and tap real widgets, then runs the full app (real
// veilid). build with:
//   flutter build apk --debug -t test/driver/app.dart \
//     --dart-define=VEILIST_IPV4_ONLY=true
//
// this drives the real ui, not the repository, so it is a true end-to-end test.

import 'package:flutter_driver/driver_extension.dart';
import 'package:veilist/main.dart' as app;
import 'package:veilist/veilid/veilid_service.dart';

void main() {
  // must run before any binding exists: it installs its own driver binding and
  // asserts none is initialized yet. app.main() then reuses that binding. the
  // handler is an out-of-band control channel (driver requestData) the widget
  // frontends use to simulate going offline/backgrounded (see _handle).
  enableFlutterDriverExtension(handler: _handle);
  app.main();
}

// e2e control commands delivered over the driver's requestData channel. the ui
// has no such controls, so tests reach the node/repository directly to prove
// that edits made while offline flush once the node re-attaches - on the listing
// (foreground sync running) and backgrounded (it is not).
Future<String> _handle(String? command) async {
  switch (command) {
    case 'offline':
      await VeilidService.instance.setOnline(false);
    case 'online':
      await VeilidService.instance.setOnline(true);
    case 'background':
      await app.e2eRepository?.stopForegroundSync();
    case 'foreground':
      await app.e2eRepository?.startForegroundSync();
    default:
      return 'unknown:$command';
  }
  return 'ok';
}

// e2e entrypoint for the appium flutter-driver ui tests (see test/e2e/appium/).
// exposes flutter's driver extension so an external appium test can find and
// tap real widgets, then runs the full app (real veilid). build with:
//   flutter build apk --debug -t test/driver/app.dart \
//     --dart-define=VEILIST_IPV4_ONLY=true
//
// this drives the real ui, not the repository, so it is a true end-to-end test.

import 'package:flutter_driver/driver_extension.dart';
import 'package:veilist/main.dart' as app;

void main() {
  // must run before any binding exists: it installs its own driver binding and
  // asserts none is initialized yet. app.main() then reuses that binding.
  enableFlutterDriverExtension();
  app.main();
}

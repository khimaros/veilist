import 'dart:async';
import 'dart:js_interop';

// binds to globalThis.addEventListener, i.e. window.addEventListener in the
// page. pure dart:js_interop, so no extra package dependency (mirrors
// phase_signal_web.dart).
@JS('addEventListener')
external void _addEventListener(JSString type, JSFunction listener);

/// url hash changes inside an already-open tab - e.g. a share link pasted into
/// it. flutter does not surface these, and app_links does not fire for in-page
/// hash changes, so we listen directly.
Stream<Uri> hashChanges() {
  final controller = StreamController<Uri>.broadcast();
  _addEventListener(
    'hashchange'.toJS,
    ((JSObject _) => controller.add(Uri.base)).toJS,
  );
  return controller.stream;
}

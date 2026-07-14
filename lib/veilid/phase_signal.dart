// publishes the veilid connection phase somewhere an out-of-app browser test
// can observe it. on web this sets window.veilistPhase; elsewhere it is a no-op.
// this is the only hook the browser e2e needs to confirm veilid actually runs
// (and attaches) inside the page, not merely that the page loaded.
export 'phase_signal_stub.dart'
    if (dart.library.js_interop) 'phase_signal_web.dart';

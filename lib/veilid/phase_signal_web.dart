import 'dart:js_interop';

// binds to globalThis.veilistPhase, i.e. window.veilistPhase in the page.
@JS('veilistPhase')
external set _veilistPhase(JSString value);

/// expose the current phase to the surrounding page for the browser e2e.
void publishPhase(String phase) => _veilistPhase = phase.toJS;

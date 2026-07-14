// owns the veilid node lifecycle for the whole app: core init, startup, attach,
// and the single update stream. everything else (the list repository, the ui)
// talks to the network through this one service and its routing context.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:veilid/veilid.dart';

import 'phase_signal.dart';

// identifies our on-disk stores; a stable namespace keeps a device's lists
// across restarts.
const String _programName = 'veilist';
const String _namespace = 'veilist';

// --dart-define=VEILIST_VERBOSE=true streams veilid's own logs (for diagnosing
// attach/network issues, e.g. on emulators).
const bool _verbose = bool.fromEnvironment('VEILIST_VERBOSE');

// --dart-define=VEILIST_IPV4_ONLY=true restricts veilid to ipv4 (needed on
// emulators; see startup()).
const bool _ipv4Only = bool.fromEnvironment('VEILIST_IPV4_ONLY');
const VeilidConfigLogLevel _apiLogLevel = _verbose
    ? VeilidConfigLogLevel.debug
    : VeilidConfigLogLevel.info;

/// lifecycle phases surfaced to the ui.
enum VeilidPhase { stopped, starting, attaching, ready, error }

/// singleton veilid node. a [ChangeNotifier] so widgets rebuild as the node
/// starts, attaches, and reaches the public internet.
class VeilidService extends ChangeNotifier {
  VeilidService._();
  static final VeilidService instance = VeilidService._();

  Stream<VeilidUpdate>? _updateStream;
  StreamSubscription<VeilidUpdate>? _sub;
  VeilidRoutingContext? _routingContext;

  VeilidPhase _phase = VeilidPhase.stopped;
  AttachmentState _attachment = AttachmentState.detached;
  bool _publicInternetReady = false;
  String? _lastError;

  // dht watch notifications, rebroadcast for the list repository to fold live.
  final _valueChanges = StreamController<VeilidUpdateValueChange>.broadcast();

  VeilidPhase get phase => _phase;
  AttachmentState get attachment => _attachment;
  bool get publicInternetReady => _publicInternetReady;
  String? get lastError => _lastError;

  /// true once the node can actually reach the dht.
  bool get isReady => _phase == VeilidPhase.ready;

  /// the shared routing context. valid only after [startup] completes.
  VeilidRoutingContext get routingContext {
    final rc = _routingContext;
    if (rc == null) throw StateError('veilid not started');
    return rc;
  }

  Stream<VeilidUpdateValueChange> get valueChanges => _valueChanges.stream;

  /// start the node and attach to the network. idempotent.
  Future<void> startup() async {
    if (_phase != VeilidPhase.stopped && _phase != VeilidPhase.error) return;
    try {
      _setPhase(VeilidPhase.starting);
      Veilid.instance.initializeVeilidCore(_platformConfig());

      var config = await getDefaultVeilidConfig(
        isWeb: kIsWeb,
        programName: _programName,
        namespace: _namespace,
      );
      // on android release builds the keystore-backed protected store fails to
      // initialize ("could not initialize the protected store"); allow veilid
      // to fall back to file storage in the app's private directory so startup
      // succeeds. debug builds happen to init the secure store fine.
      config = config.copyWith(
        protectedStore: config.protectedStore.copyWith(
          allowInsecureFallback: true,
        ),
      );
      if (_ipv4Only) {
        // emulator mode. force ipv4: the slirp site-local ipv6 is misdetected
        // as global and stalls bootstrap. require an inbound relay: the emulator
        // is behind slirp nat but its private address is taken as directly
        // reachable, so without a relay peers cannot reach the node and dht
        // watches/reads never converge.
        config = config.copyWith(
          network: config.network.copyWith(
            addressTypes: const [VeilidConfigAddressType.ipv4],
            privacy: const VeilidConfigPrivacy(requireInboundRelay: true),
          ),
        );
      }
      _updateStream = await Veilid.instance.startupVeilidCore(config);
      _sub = _updateStream!.listen(_onUpdate, onError: _onStreamError);
      _routingContext = await Veilid.instance.routingContext();

      _setPhase(VeilidPhase.attaching);
      await Veilid.instance.attach();
    } on Exception catch (e) {
      _fail('$e');
    }
  }

  Future<void> shutdown() async {
    await _sub?.cancel();
    _sub = null;
    _routingContext?.close();
    _routingContext = null;
    if (_phase != VeilidPhase.stopped) {
      await Veilid.instance.shutdownVeilidCore();
    }
    _attachment = AttachmentState.detached;
    _publicInternetReady = false;
    _setPhase(VeilidPhase.stopped);
  }

  void _onUpdate(VeilidUpdate update) {
    switch (update) {
      case VeilidUpdateAttachment():
        _attachment = update.state;
        _publicInternetReady = update.publicInternetReady;
        // "ready" means attached AND able to reach the public dht, which is
        // what dht record operations actually require.
        if (_publicInternetReady) {
          _setPhase(VeilidPhase.ready);
        } else if (_phase == VeilidPhase.ready) {
          _setPhase(VeilidPhase.attaching);
        } else {
          notifyListeners();
        }
      case VeilidUpdateValueChange():
        _valueChanges.add(update);
      case VeilidLog():
        if (_verbose || update.logLevel == VeilidLogLevel.error) {
          debugPrint('veilid[${update.logLevel.name}]: ${update.message}');
        }
      default:
        break;
    }
  }

  void _onStreamError(Object error, StackTrace _) => _fail('$error');

  void _fail(String message) {
    _lastError = message;
    _setPhase(VeilidPhase.error);
  }

  void _setPhase(VeilidPhase p) {
    _phase = p;
    publishPhase(p.name); // observable by the browser e2e on web
    notifyListeners();
  }

  // logging-only platform config; the network config comes from
  // getDefaultVeilidConfig. mirrors the veilid plugin example.
  Map<String, dynamic> _platformConfig() {
    if (kIsWeb) {
      return const VeilidWASMConfig(
        logging: VeilidWASMConfigLogging(
          performance: VeilidWASMConfigLoggingPerformance(
            enabled: false,
            level: VeilidConfigLogLevel.debug,
          ),
          api: VeilidWASMConfigLoggingApi(enabled: true, level: _apiLogLevel),
        ),
      ).toJson();
    }
    return const VeilidFFIConfig(
      logging: VeilidFFIConfigLogging(
        terminal: VeilidFFIConfigLoggingTerminal(
          enabled: false,
          level: VeilidConfigLogLevel.debug,
        ),
        api: VeilidFFIConfigLoggingApi(enabled: true, level: _apiLogLevel),
      ),
    ).toJson();
  }

  @override
  void dispose() {
    _valueChanges.close();
    super.dispose();
  }
}

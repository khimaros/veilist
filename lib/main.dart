// app entrypoint: boot the veilid node, load the saved list roster, and start
// handling share links, then show the listing page.

import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'data/list_network.dart';
import 'data/list_repository.dart';
import 'data/list_store.dart';
import 'e2e/test_hook.dart';
import 'ui/link_handler.dart';
import 'ui/listing_page.dart';
import 'veilid/veilid_service.dart';

// only true for e2e builds (--dart-define=VEILIST_E2E=1); gates the test hook.
const bool _e2e = bool.fromEnvironment('VEILIST_E2E');

// fallback accent when the platform has no dynamic color; matches the gnome/
// libadwaita default "blue" accent (#3584e4).
const Color _seed = Color(0xFF3584E4);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final service = VeilidService.instance;
  final repository = ListRepository(
    store: TableListStore(),
    network: VeilidListNetwork(service),
  );
  runApp(VeilistApp(service: service, repository: repository));
}

class VeilistApp extends StatefulWidget {
  const VeilistApp({
    super.key,
    required this.service,
    required this.repository,
  });

  final VeilidService service;
  final ListRepository repository;

  @override
  State<VeilistApp> createState() => _VeilistAppState();
}

class _VeilistAppState extends State<VeilistApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final LinkHandler _linkHandler = LinkHandler(
    repository: widget.repository,
    navigatorKey: _navigatorKey,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // keep every list synced only while the app is foregrounded; release the
  // watches when it is backgrounded.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.repository.startForegroundSync());
    } else {
      unawaited(widget.repository.stopForegroundSync());
    }
  }

  // node up -> roster loaded -> links handled. a startup failure still shows
  // the ui (with the connection bar reporting the error).
  Future<void> _boot() async {
    // install the e2e hook before any await, so it exists by the time the
    // browser test observes veilid reach 'ready' (which arrives asynchronously).
    if (_e2e) installTestHook(widget.repository);
    await widget.service.startup();
    if (widget.service.phase == VeilidPhase.error) return;
    try {
      await widget.repository.load();
    } catch (_) {
      // table store unavailable; the listing simply starts empty.
    }
    await _linkHandler.start();
    // the app launches foregrounded, but no lifecycle event fires for that
    // initial state, so kick off foreground sync here.
    unawaited(widget.repository.startForegroundSync());
  }

  @override
  Widget build(BuildContext context) {
    // material you: use the device's dynamic color when available (android
    // 12+), otherwise a seed color. dark mode by default.
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final light = lightDynamic ?? ColorScheme.fromSeed(seedColor: _seed);
        final dark =
            darkDynamic ??
            ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark);
        return MaterialApp(
          title: 'veilist',
          debugShowCheckedModeBanner: false,
          navigatorKey: _navigatorKey,
          themeMode: ThemeMode.dark,
          theme: ThemeData(colorScheme: light, useMaterial3: true),
          darkTheme: ThemeData(colorScheme: dark, useMaterial3: true),
          home: ListingPage(repository: widget.repository),
        );
      },
    );
  }
}

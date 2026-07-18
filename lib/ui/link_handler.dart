// turns incoming share links into an opened list. handles the link the app was
// launched with, links delivered while running, and - on web - a link pasted
// into an already-open tab (R2). on web the launch url lives in the page
// fragment, which app_links surfaces too.

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/list_repository.dart';
import '../data/share_link.dart';
import 'list_detail_page.dart';
import 'web_url.dart';

class LinkHandler {
  LinkHandler({required this.repository, required this.navigatorKey});

  final ListRepository repository;
  final GlobalKey<NavigatorState> navigatorKey;
  final _appLinks = AppLinks();

  /// the share link the app was launched with, if any, without opening it. read
  /// once at boot so the ui can show a loading screen for a launch link instead
  /// of flashing the listing while the node starts and the join runs. on web the
  /// launch url is the page fragment (Uri.base); on native it comes from
  /// app_links.
  Future<ShareLink?> initialLink() async {
    final uri = kIsWeb ? Uri.base : await _appLinks.getInitialLink();
    return uri == null ? null : ShareLink.tryParse(uri);
  }

  /// subscribe to links delivered while the app runs: a veilist:// intent, and -
  /// on web - a link pasted into the already-open tab (a hash change neither
  /// flutter nor app_links surfaces).
  void listen() {
    if (kIsWeb) hashChanges().listen(_tryOpen);
    _appLinks.uriLinkStream.listen(_tryOpen);
  }

  /// join the list and open its detail page. [animate] is false for the launch
  /// link, which opens from behind the loading screen - a slide-in would reveal
  /// the listing underneath - so it uses a zero-duration transition; live links
  /// animate in over whatever is already on screen.
  Future<void> open(ShareLink link, {bool animate = true}) async {
    final local = await repository.joinList(link);
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    final page = ListDetailPage(repository: repository, local: local);
    // not awaited: push completes only when the route is popped, and the boot
    // path drops the loading screen as soon as the page is on screen.
    unawaited(
      nav.push(
        animate
            ? MaterialPageRoute<void>(builder: (_) => page)
            : PageRouteBuilder<void>(
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
                pageBuilder: (_, _, _) => page,
              ),
      ),
    );
  }

  Future<void> _tryOpen(Uri uri) async {
    final link = ShareLink.tryParse(uri);
    if (link != null) await open(link);
  }
}

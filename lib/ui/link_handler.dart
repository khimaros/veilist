// turns incoming share links into an opened list. handles the link the app was
// launched with, links delivered while running, and - on web - a link pasted
// into an already-open tab (R2). on web the launch url lives in the page
// fragment, which app_links surfaces too.

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

  /// begin handling the launch link and every later source of links.
  Future<void> start() async {
    if (kIsWeb) {
      await _tryOpen(Uri.base);
      // a link pasted into the already-open tab arrives as a hash change, which
      // neither flutter nor app_links surfaces.
      hashChanges().listen(_tryOpen);
    }
    final initial = await _appLinks.getInitialLink();
    if (initial != null) await _tryOpen(initial);
    _appLinks.uriLinkStream.listen(_tryOpen);
  }

  Future<void> _tryOpen(Uri uri) async {
    final link = ShareLink.tryParse(uri);
    if (link == null) return;
    final local = await repository.joinList(link);
    await navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => ListDetailPage(repository: repository, local: local),
      ),
    );
  }
}

// the home page: every list this device has created or opened (R5), with
// per-list open, share, and delete (R6). also shows the veilid connection
// state and lets the user join a list by scanning or pasting a share link.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/list_repository.dart';
import '../data/local_list.dart';
import '../data/share_link.dart';
import '../veilid/veilid_service.dart';
import 'list_detail_page.dart';
import 'scan_page.dart';

class ListingPage extends StatelessWidget {
  const ListingPage({super.key, required this.repository});

  final ListRepository repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('veilist'),
        actions: [
          if (canScanLinks)
            IconButton(
              key: const Key('scan_link_button'),
              tooltip: 'scan a shared link',
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () => _scanLink(context),
            ),
          IconButton(
            key: const Key('open_link_button'),
            tooltip: 'open a shared link',
            icon: const Icon(Icons.link),
            onPressed: () => _openLink(context),
          ),
          // the connection status sits at the far right on every screen.
          _ConnectionStatus(VeilidService.instance),
        ],
        bottom: _ConnectionBar(VeilidService.instance),
      ),
      body: ListenableBuilder(
        listenable: repository,
        builder: (context, _) {
          final lists = repository.lists;
          if (lists.isEmpty) {
            return const _EmptyState();
          }
          return ListView.builder(
            itemCount: lists.length,
            itemBuilder: (context, i) =>
                _ListTile(list: lists[i], repository: repository),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('fab_new_list'),
        onPressed: () => _createList(context),
        icon: const Icon(Icons.add),
        label: const Text('new list'),
      ),
    );
  }

  Future<void> _createList(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final title = await _promptText(
      context,
      title: 'new list',
      hint: 'list name',
      action: 'create',
    );
    if (title == null || title.trim().isEmpty) return;
    try {
      await repository.createList(title.trim());
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('could not create: $e')));
    }
  }

  Future<void> _openLink(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final text = await _promptText(
      context,
      title: 'open a shared link',
      hint: 'paste link',
      action: 'open',
    );
    if (text == null || text.trim().isEmpty) return;
    final link = shareLinkFromCode(text);
    if (link == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('not a veilist link')),
      );
      return;
    }
    await _join(navigator, messenger, link);
  }

  /// read a list's qr code with the camera and join it (R1, R2).
  Future<void> _scanLink(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final link = await scanShareLink(context);
    if (link != null) await _join(navigator, messenger, link);
  }

  Future<void> _join(
    NavigatorState navigator,
    ScaffoldMessengerState messenger,
    ShareLink link,
  ) async {
    try {
      final local = await repository.joinList(link);
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ListDetailPage(repository: repository, local: local),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('could not open: $e')));
    }
  }
}

class _ListTile extends StatelessWidget {
  const _ListTile({required this.list, required this.repository});

  final LocalList list;
  final ListRepository repository;

  @override
  Widget build(BuildContext context) {
    final subtitle = list.isOwner ? 'created by you' : 'shared with you';
    return ListTile(
      leading: CircleAvatar(
        child: Icon(list.isOwner ? Icons.edit_note : Icons.group),
      ),
      title: Text(list.title.isEmpty ? '(untitled list)' : list.title),
      subtitle: Text(subtitle),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ListDetailPage(repository: repository, local: list),
        ),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'share') _share(context);
          if (v == 'rename') _rename(context);
          if (v == 'delete') _delete(context);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'share', child: Text('share')),
          PopupMenuItem(value: 'rename', child: Text('rename')),
          PopupMenuItem(value: 'delete', child: Text('delete')),
        ],
      ),
    );
  }

  Future<void> _share(BuildContext context) async {
    final link = await repository.shareList(list);
    if (!context.mounted) return;
    await showShareDialog(context, link);
  }

  Future<void> _rename(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final title = await _promptText(
      context,
      title: 'rename list',
      hint: 'list name',
      action: 'rename',
    );
    if (title == null || title.trim().isEmpty) return;
    try {
      await repository.renameList(list, title.trim());
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('could not rename: $e')));
    }
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('delete list?'),
        content: Text(
          'remove "${list.title.isEmpty ? 'this list' : list.title}" from '
          'this device. others keep their copy.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await repository.deleteList(list);
  }
}

/// shows both link forms with copy buttons. shared by listing and detail.
Future<void> showShareDialog(BuildContext context, ShareLink link) {
  return showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('share this list'),
      // a bounded width avoids AlertDialog querying the content's intrinsic
      // width, which fails because _CopyRow uses an Expanded inside a Row.
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('anyone with this link can view and edit the list.'),
              const SizedBox(height: 12),
              // white background + black modules so the code scans in dark mode.
              Center(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(8),
                  child: QrImageView(
                    data: link.toAppUri().toString(),
                    version: QrVersions.auto,
                    size: 180,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _CopyRow(
                label: 'app link',
                value: link.toAppUri().toString(),
                valueKey: const Key('app_link_value'),
              ),
              _CopyRow(label: 'web link', value: link.toWebUri().toString()),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('done'),
        ),
      ],
    ),
  );
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.label, required this.value, this.valueKey});

  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                Text(
                  value,
                  key: valueKey,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'copy',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('copied')));
            },
          ),
        ],
      ),
    );
  }
}

// a visible, tappable veilid status in the app bar. it doubles as the sync
// indicator: lists and items are created/edited locally right away, and this
// shows whether those changes are syncing to the network yet.
class _ConnectionStatus extends StatelessWidget {
  const _ConnectionStatus(this.service);

  final VeilidService service;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final s = _statusFor(context);
        return IconButton(
          key: const Key('connection_status'),
          tooltip: 'veilid: ${s.label}',
          icon: Icon(s.icon, color: s.color),
          onPressed: () => _showDetails(context, s),
        );
      },
    );
  }

  _Status _statusFor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (service.phase) {
      case VeilidPhase.ready:
        return _Status(
          Icons.cloud_done,
          null,
          'online',
          'connected to the network. changes sync instantly.',
        );
      case VeilidPhase.starting:
      case VeilidPhase.attaching:
        return _Status(
          Icons.cloud_sync,
          scheme.onSurfaceVariant,
          'connecting',
          'connecting to the network. changes are saved on this device and '
              'will sync once connected.',
        );
      case VeilidPhase.error:
        return _Status(
          Icons.cloud_off,
          scheme.error,
          'offline',
          'not connected (${service.lastError ?? 'error'}). changes are '
              'saved on this device and sync when reconnected.',
        );
      case VeilidPhase.stopped:
        return _Status(
          Icons.cloud_off,
          scheme.onSurfaceVariant,
          'offline',
          'not connected. changes are saved on this device.',
        );
    }
  }

  Future<void> _showDetails(BuildContext context, _Status s) {
    return showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(s.icon, color: s.color),
            const SizedBox(width: 8),
            Text('veilid: ${s.label}'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.detail),
            const SizedBox(height: 12),
            Text(
              'attachment: ${service.attachment.name}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'public internet: ${service.publicInternetReady}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('close'),
          ),
        ],
      ),
    );
  }
}

class _Status {
  const _Status(this.icon, this.color, this.label, this.detail);

  final IconData icon;
  final Color? color;
  final String label;
  final String detail;
}

class _ConnectionBar extends StatelessWidget implements PreferredSizeWidget {
  const _ConnectionBar(this.service);

  final VeilidService service;

  @override
  Size get preferredSize => const Size.fromHeight(4);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        // a thin progress line only while actively connecting; nothing once
        // ready or before boot, an error stripe on failure.
        switch (service.phase) {
          case VeilidPhase.error:
            return Container(
              height: 4,
              color: Theme.of(context).colorScheme.error,
            );
          case VeilidPhase.starting:
          case VeilidPhase.attaching:
            return const LinearProgressIndicator(minHeight: 4);
          case VeilidPhase.stopped:
          case VeilidPhase.ready:
            return const SizedBox(height: 4);
        }
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.checklist, size: 64),
          const SizedBox(height: 12),
          Text('no lists yet', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('create one, or open a link someone shared'),
        ],
      ),
    );
  }
}

/// a small single-field prompt dialog returning the entered text or null.
Future<String?> _promptText(
  BuildContext context, {
  required String title,
  required String hint,
  required String action,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        key: const Key('prompt_field'),
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('cancel'),
        ),
        FilledButton(
          key: const Key('prompt_action'),
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(action),
        ),
      ],
    ),
  );
}

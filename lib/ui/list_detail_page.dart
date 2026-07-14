// a single list: its items, each with a checkbox that cycles item states
// (R7), plus add/edit/delete and a share action. drives an [OpenList], which
// folds every member's contributions and pushes this device's edits.

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/list_repository.dart';
import '../data/local_list.dart';
import '../data/open_list.dart';
import '../models/crdt.dart';
import '../models/item_state.dart';
import 'listing_page.dart' show showShareDialog;

class ListDetailPage extends StatefulWidget {
  const ListDetailPage({
    super.key,
    required this.repository,
    required this.local,
  });

  final ListRepository repository;
  final LocalList local;

  @override
  State<ListDetailPage> createState() => _ListDetailPageState();
}

class _ListDetailPageState extends State<ListDetailPage>
    with WidgetsBindingObserver {
  final _addController = TextEditingController();
  final _addFocus = FocusNode();

  // a per-session view filter: hide items already marked complete. reordering
  // is disabled while this is on, so visible and full indices cannot diverge.
  bool _hideCompleted = false;

  // true while the first share is publishing the list to the dht, so the share
  // button can show progress.
  bool _publishing = false;

  late OpenList _open;
  late bool _wasPublished;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open = widget.repository.open(widget.local);
    _wasPublished = widget.local.published;
    _open.open();
    // sharing a local-only list publishes it, swapping its local network for
    // the dht one, so rebuild the OpenList when that transition happens.
    widget.repository.addListener(_onRepositoryChanged);
  }

  void _onRepositoryChanged() {
    if (widget.local.published == _wasPublished) return;
    _wasPublished = widget.local.published;
    final previous = _open;
    _open = widget.repository.open(widget.local);
    previous.dispose();
    _open.open();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.repository.removeListener(_onRepositoryChanged);
    _addController.dispose();
    _addFocus.dispose();
    _open.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // the watch only delivers changes that arrive while we are connected, so
    // edits made by other devices while we were backgrounded are missed. force
    // a fresh read on resume to catch up.
    if (state == AppLifecycleState.resumed) {
      unawaited(_open.refresh().catchError((Object _) {}));
    }
  }

  Future<void> _share() async {
    // the first share publishes to the dht, which takes a network round-trip;
    // turn the share button into a spinner so the delay is not silent.
    if (!widget.local.published) setState(() => _publishing = true);
    try {
      final link = await widget.repository.shareList(widget.local);
      if (mounted) await showShareDialog(context, link);
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _open,
      builder: (context, _) {
        final open = _open;
        return Scaffold(
          appBar: AppBar(
            // anyone who can edit renames by tapping the title; a not-yet-
            // editable shared list shows a plain title.
            title: _Title(open: open, onRename: () => _rename(open)),
            actions: [
              if (open.items.isNotEmpty)
                IconButton(
                  key: const Key('toggle_completed'),
                  tooltip: _hideCompleted ? 'show completed' : 'hide completed',
                  icon: Icon(
                    _hideCompleted ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () =>
                      setState(() => _hideCompleted = !_hideCompleted),
                ),
              IconButton(
                tooltip: _publishing ? 'publishing...' : 'share',
                icon: _publishing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.share),
                onPressed: _publishing ? null : _share,
              ),
              // the sync/connection status sits at the far right on every screen.
              _SyncChip(open),
            ],
          ),
          // the add bar lives in the body (not bottomNavigationBar, which stays
          // behind the keyboard) so resizeToAvoidBottomInset lifts it with the
          // keyboard and keeps it visible.
          body: Column(
            children: [
              Expanded(child: _body(open)),
              _addBar(open),
            ],
          ),
        );
      },
    );
  }

  Widget _body(OpenList open) {
    if (open.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (open.error != null) {
      return Center(child: Text('could not open list:\n${open.error}'));
    }
    // a joined list stays read-only until its first sync lands, so the recipient
    // never edits an empty list that the real data then overwrites.
    if (open.awaitingInitialSync) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('syncing the shared list...'),
          ],
        ),
      );
    }
    if (open.items.isEmpty) {
      return const Center(child: Text('no items yet - add one below'));
    }
    final visible = _hideCompleted
        ? open.items.where((i) => i.state != ItemState.complete).toList()
        : open.items;
    if (visible.isEmpty) {
      return const Center(child: Text('all items complete'));
    }
    // drag the handle to reorder; the tile itself stays free for tap-to-edit
    // and swipe-to-delete. reordering is off while completed items are hidden,
    // so the visible indices always match the full list.
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemCount: visible.length,
      onReorderItem: open.reorder,
      itemBuilder: (context, i) => _ItemTile(
        key: ValueKey(visible[i].id),
        index: i,
        item: visible[i],
        open: open,
        canReorder: !_hideCompleted,
        onEdit: () => _editItem(open, visible[i]),
      ),
    );
  }

  Future<void> _editItem(OpenList open, ListItem item) async {
    final controller = TextEditingController(text: item.text);
    final next = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('edit item'),
        content: TextField(
          key: const Key('edit_field'),
          controller: controller,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('save'),
          ),
        ],
      ),
    );
    if (next != null && next.trim().isNotEmpty) open.setText(item.id, next);
  }

  Widget _addBar(OpenList open) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('add_field'),
                controller: _addController,
                focusNode: _addFocus,
                // a joined list is read-only until its first sync lands.
                enabled: open.canEdit,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: open.canEdit ? 'add an item' : 'syncing...',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _add(open),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const Key('add_button'),
              onPressed: open.canEdit ? () => _add(open) : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }

  void _add(OpenList open) {
    final text = _addController.text.trim();
    if (text.isEmpty) return;
    open.addItem(text);
    _addController.clear();
    // keep the field focused so the next item can be typed without re-tapping.
    _addFocus.requestFocus();
  }

  Future<void> _rename(OpenList open) async {
    final controller = TextEditingController(text: open.title);
    final next = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('rename list'),
        content: TextField(
          key: const Key('rename_field'),
          controller: controller,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('save'),
          ),
        ],
      ),
    );
    if (next != null && next.trim().isNotEmpty) open.setTitle(next.trim());
  }
}

// the app-bar title. anyone who can edit taps it to rename; a not-yet-editable
// shared list shows a plain, non-interactive title.
class _Title extends StatelessWidget {
  const _Title({required this.open, required this.onRename});

  final OpenList open;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final text = open.title.isEmpty ? '(untitled list)' : open.title;
    const key = Key('list_title');
    // anyone who can edit the list can rename it by tapping the title (owners
    // always; members once synced). a not-yet-editable shared list is plain.
    if (!open.canEdit) {
      return Text(text, key: key, overflow: TextOverflow.ellipsis);
    }
    return InkWell(
      onTap: onRename,
      child: Text(text, key: key, overflow: TextOverflow.ellipsis),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    super.key,
    required this.index,
    required this.item,
    required this.open,
    required this.canReorder,
    required this.onEdit,
  });

  final int index;
  final ListItem item;
  final OpenList open;
  final bool canReorder;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final done = item.state == ItemState.complete;
    return Dismissible(
      key: ValueKey('dismiss_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete),
      ),
      onDismissed: (_) => open.removeItem(item.id),
      child: ListTile(
        leading: StateGlyphButton(
          state: item.state,
          onTap: () => open.cycleState(item.id),
        ),
        title: Text(
          item.text,
          style: done
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        onTap: onEdit, // tap to edit the item text
        trailing: canReorder
            ? ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.drag_handle),
                ),
              )
            : null,
      ),
    );
  }
}

/// shows whether this device's edits have reached the network. rebuilds with
/// the page (the OpenList notifies on sync-status changes).
class _SyncChip extends StatelessWidget {
  const _SyncChip(this.open);

  final OpenList open;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final (
      IconData icon,
      Color? color,
      String label,
    ) = switch (open.syncStatus) {
      SyncStatus.synced => (Icons.cloud_done, null, 'synced'),
      SyncStatus.syncing => (Icons.cloud_sync, muted, 'syncing'),
      SyncStatus.offline => (Icons.cloud_off, muted, 'offline'),
      SyncStatus.local => (Icons.smartphone, muted, 'saved on this device'),
    };
    return IconButton(
      tooltip: 'changes are $label',
      icon: Icon(icon, color: color),
      onPressed: () => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('changes are $label'))),
    );
  }
}

/// the checkbox: a bordered glyph box that cycles item states on tap (R7). the
/// glyph matches the plain-text notation, e.g. `[ ]`, `[x]`.
class StateGlyphButton extends StatelessWidget {
  const StateGlyphButton({super.key, required this.state, required this.onTap});

  final ItemState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 27,
        height: 27,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outline),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          state.glyph.trim().isEmpty ? '' : state.glyph,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

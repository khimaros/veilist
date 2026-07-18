import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../data/list_repository.dart';
import '../data/open_list.dart';
import '../data/share_link.dart';
import '../models/item_state.dart';
import '../veilid/veilid_service.dart';

/// exposes `window.veilistTest` with async list operations, each returning a
/// promise. lets the browser e2e (and the compliance matrix's web frontend)
/// drive real list operations over the live dht without touching flutter's
/// canvas ui. installed only for e2e builds. the surface mirrors the user
/// actions the shared compliance flows need.
void installTestHook(ListRepository repo) {
  final open = <String, OpenList>{};

  Future<OpenList> ensureOpen(String recordKey) async {
    final existing = open[recordKey];
    if (existing != null) return existing;
    final local = repo.lists.firstWhere((l) => l.recordKey == recordKey);
    final opened = repo.open(local);
    await opened.open();
    open[recordKey] = opened;
    return opened;
  }

  JSPromise<JSString> create(JSString title) => (() async {
    final list = await repo.createList(title.toDart);
    return list.recordKey.toJS;
  })().toJS;

  JSPromise<JSString> share(JSString recordKey) => (() async {
    final local = repo.lists.firstWhere((l) => l.recordKey == recordKey.toDart);
    final link = await repo.shareList(local);
    // shareList may publish and re-key the list; return the up-to-date link.
    return link.toAppUri().toString().toJS;
  })().toJS;

  JSPromise<JSString> join(JSString link) => (() async {
    final parsed = ShareLink.tryParse(Uri.parse(link.toDart))!;
    final local = await repo.joinList(parsed);
    return local.recordKey.toJS;
  })().toJS;

  JSPromise<JSString> add(JSString recordKey, JSString text) => (() async {
    final opened = await ensureOpen(recordKey.toDart);
    await opened.addItem(text.toDart);
    return 'ok'.toJS;
  })().toJS;

  JSPromise<JSString> toggle(JSString recordKey, JSString id) => (() async {
    final opened = await ensureOpen(recordKey.toDart);
    await opened.toggleState(id.toDart);
    return 'ok'.toJS;
  })().toJS;

  JSPromise<JSString> setItemState(
    JSString recordKey,
    JSString id,
    JSString code,
  ) => (() async {
    final opened = await ensureOpen(recordKey.toDart);
    await opened.setItemState(id.toDart, ItemState.fromCode(code.toDart));
    return 'ok'.toJS;
  })().toJS;

  JSPromise<JSString> removeItem(JSString recordKey, JSString id) => (() async {
    final opened = await ensureOpen(recordKey.toDart);
    await opened.removeItem(id.toDart);
    return 'ok'.toJS;
  })().toJS;

  JSPromise<JSString> setText(JSString recordKey, JSString id, JSString text) =>
      (() async {
        final opened = await ensureOpen(recordKey.toDart);
        await opened.setText(id.toDart, text.toDart);
        return 'ok'.toJS;
      })().toJS;

  JSPromise<JSString> reorder(
    JSString recordKey,
    JSNumber oldIndex,
    JSNumber newIndex,
  ) => (() async {
    final opened = await ensureOpen(recordKey.toDart);
    await opened.reorder(oldIndex.toDartInt, newIndex.toDartInt);
    return 'ok'.toJS;
  })().toJS;

  JSPromise<JSString> setTitle(JSString recordKey, JSString title) =>
      (() async {
        final opened = await ensureOpen(recordKey.toDart);
        await opened.setTitle(title.toDart);
        return 'ok'.toJS;
      })().toJS;

  JSPromise<JSString> deleteList(JSString recordKey) => (() async {
    final local = repo.lists.firstWhere((l) => l.recordKey == recordKey.toDart);
    await repo.deleteList(local);
    open.remove(recordKey.toDart);
    return 'ok'.toJS;
  })().toJS;

  // returns the folded items as a json array of {id, text, state}.
  JSPromise<JSString> items(JSString recordKey) => (() async {
    final opened = await ensureOpen(recordKey.toDart);
    final data = [
      for (final item in opened.items)
        {'id': item.id, 'text': item.text, 'state': item.state.code},
    ];
    return jsonEncode(data).toJS;
  })().toJS;

  JSPromise<JSString> title(JSString recordKey) => (() async {
    final opened = await ensureOpen(recordKey.toDart);
    return opened.title.toJS;
  })().toJS;

  JSPromise<JSString> syncStatus(JSString recordKey) => (() async {
    final opened = await ensureOpen(recordKey.toDart);
    return opened.syncStatus.name.toJS;
  })().toJS;

  JSPromise<JSString> editable(JSString recordKey) => (() async {
    final opened = await ensureOpen(recordKey.toDart);
    return (opened.canEdit ? 'true' : 'false').toJS;
  })().toJS;

  // take the node offline/online (detach/attach), to test that edits made while
  // offline flush once re-attached.
  JSPromise<JSString> setOnline(JSBoolean online) => (() async {
    await VeilidService.instance.setOnline(online.toDart);
    return 'ok'.toJS;
  })().toJS;

  // toggle foreground sync, to simulate the app being backgrounded (off) versus
  // sitting on the listing (on).
  JSPromise<JSString> setForeground(JSBoolean foreground) => (() async {
    await (foreground.toDart
        ? repo.startForegroundSync()
        : repo.stopForegroundSync());
    return 'ok'.toJS;
  })().toJS;

  // the roster as a json array of {recordKey, title, published}.
  JSString lists() {
    final data = [
      for (final l in repo.lists)
        {'recordKey': l.recordKey, 'title': l.title, 'published': l.published},
    ];
    return jsonEncode(data).toJS;
  }

  final hook = JSObject();
  hook.setProperty('create'.toJS, create.toJS);
  hook.setProperty('share'.toJS, share.toJS);
  hook.setProperty('join'.toJS, join.toJS);
  hook.setProperty('add'.toJS, add.toJS);
  hook.setProperty('toggle'.toJS, toggle.toJS);
  hook.setProperty('setItemState'.toJS, setItemState.toJS);
  hook.setProperty('removeItem'.toJS, removeItem.toJS);
  hook.setProperty('setText'.toJS, setText.toJS);
  hook.setProperty('reorder'.toJS, reorder.toJS);
  hook.setProperty('setTitle'.toJS, setTitle.toJS);
  hook.setProperty('deleteList'.toJS, deleteList.toJS);
  hook.setProperty('items'.toJS, items.toJS);
  hook.setProperty('title'.toJS, title.toJS);
  hook.setProperty('syncStatus'.toJS, syncStatus.toJS);
  hook.setProperty('editable'.toJS, editable.toJS);
  hook.setProperty('setOnline'.toJS, setOnline.toJS);
  hook.setProperty('setForeground'.toJS, setForeground.toJS);
  hook.setProperty('lists'.toJS, lists.toJS);
  globalContext.setProperty('veilistTest'.toJS, hook);
}

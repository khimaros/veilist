// a local-only ListNetwork for a list created on this device but not yet shared
// (R8): edits persist on-device and nothing touches the veilid dht. the backing
// store is the creator's single MemberDoc json; on the first share the
// repository publishes it to a real record and swaps in the veilid network.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'list_network.dart';

class LocalListNetwork implements ListNetwork {
  LocalListNetwork({required String? doc, required this.onWrite}) : _doc = doc;

  String? _doc;

  /// called with the creator's doc json whenever it changes, so the repository
  /// can persist it.
  final void Function(String json) onWrite;

  // a purely local list never changes remotely, so this notifier never fires.
  static final ChangeNotifier _never = ChangeNotifier();

  @override
  bool get isReady => true;

  @override
  Listenable get readiness => _never;

  @override
  Stream<DocChange> get changes => const Stream<DocChange>.empty();

  // the creator is the sole member; the doc always lives at subkey 0.
  @override
  Future<int> openRecord(String recordKey, {required String writer}) async => 1;

  @override
  Future<Map<int, String>> readDocs(
    String recordKey,
    int memberCount, {
    bool forceRefresh = false,
  }) async => _doc == null ? const {} : {0: _doc!};

  @override
  Future<void> writeDoc(String recordKey, int memberIndex, String json) async {
    _doc = json;
    onWrite(json);
  }

  @override
  Future<bool> hasPendingWrites(String recordKey) async => false;

  @override
  Future<void> closeRecord(String recordKey) async {}

  @override
  Future<void> deleteRecord(String recordKey) async {}

  @override
  Future<CreatedRecord> createRecord() async =>
      throw UnsupportedError('a local list has no dht record');
}

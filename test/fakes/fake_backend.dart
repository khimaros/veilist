// in-memory fakes for the store and network, so the whole app can be exercised
// headlessly. a single [FakeDht] shared between two [FakeListNetwork]s lets one
// test play multiple actors (alice, bob) collaborating on the same record.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:veilist/data/dht_layout.dart';
import 'package:veilist/data/list_network.dart';
import 'package:veilist/data/list_store.dart';
import 'package:veilist/data/local_list.dart';

/// a shared fake dht: many networks can point at one instance to collaborate.
class FakeDht {
  final Map<String, _Rec> _recs = {};
  final _changes = StreamController<DocChange>.broadcast();
  int _seq = 0;

  Stream<DocChange> get changes => _changes.stream;

  CreatedRecord createRecord() {
    final key = 'VLD0:fake${_seq++}';
    final pool = [for (var i = 0; i < kMaxMembers; i++) 'VLD0:pub$i:sec$i'];
    _recs[key] = _Rec(kMaxMembers);
    return (recordKey: key, pool: pool);
  }

  int memberCount(String key) => _recs[key]?.memberCount ?? 0;

  Map<int, String> readDocs(String key) => Map.of(_recs[key]?.docs ?? const {});

  // failure injection: drop this many upcoming change notifications (the write
  // still lands in the store), simulating watch updates the network silently
  // loses, so a reader only catches them by reconciling.
  int _dropChanges = 0;

  /// drop the next [count] change notifications (writes still store).
  void dropNextChanges(int count) => _dropChanges = count;

  void writeDoc(String key, int index, String json) {
    final rec = _recs[key];
    if (rec == null) return;
    rec.docs[index] = json;
    if (_dropChanges > 0) {
      _dropChanges--;
      return; // notification lost; only a reconcile read will see this write
    }
    _changes.add((recordKey: key, memberIndex: index, json: json));
  }

  void dispose() => _changes.close();
}

class _Rec {
  _Rec(this.memberCount);
  final int memberCount;
  final Map<int, String> docs = {};
}

/// a network view onto a [FakeDht] for one actor.
class FakeListNetwork implements ListNetwork {
  FakeListNetwork(this.dht);

  final FakeDht dht;

  final ValueNotifier<bool> _ready = ValueNotifier<bool>(true);

  @override
  bool get isReady => _ready.value;

  @override
  Listenable get readiness => _ready;

  /// flip readiness (and notify), so tests can simulate a node attaching.
  void setReady(bool value) => _ready.value = value;

  @override
  Future<CreatedRecord> createRecord() async => dht.createRecord();

  @override
  Future<int> openRecord(String recordKey, {required String writer}) async =>
      dht.memberCount(recordKey);

  // the fake dht answers every read in full; tests that need a partial read
  // subclass this and say so (see open_list_sync_test.dart).
  @override
  Future<DocsRead> readDocs(
    String recordKey,
    int memberCount, {
    bool forceRefresh = false,
  }) async => (docs: dht.readDocs(recordKey), complete: true);

  @override
  Future<void> writeDoc(String recordKey, int memberIndex, String json) async =>
      dht.writeDoc(recordKey, memberIndex, json);

  @override
  Stream<DocChange> get changes => dht.changes;

  @override
  Future<bool> hasPendingWrites(String recordKey) async => false;

  @override
  Future<void> closeRecord(String recordKey) async {}

  @override
  Future<void> deleteRecord(String recordKey) async {}
}

/// in-memory store that round-trips through json to mimic real persistence.
class FakeListStore implements ListStore {
  final Map<String, Map<String, dynamic>> _rows = {};

  @override
  Future<List<LocalList>> loadAll() async =>
      _rows.values.map(LocalList.fromJson).toList();

  @override
  Future<void> save(LocalList list) async =>
      _rows[list.recordKey] = list.toJson();

  @override
  Future<void> remove(String recordKey) async => _rows.remove(recordKey);
}

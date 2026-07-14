// local persistence for the roster of known lists. an interface so tests can
// swap in an in-memory fake; the real implementation uses veilid's own
// table_db, avoiding any extra storage dependency (REQUIREMENTS.md R10).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:veilid/veilid.dart';

import 'local_list.dart';

abstract class ListStore {
  Future<List<LocalList>> loadAll();
  Future<void> save(LocalList list);
  Future<void> remove(String recordKey);
}

/// table_db-backed store. one column, keyed by record key.
class TableListStore implements ListStore {
  static const String _tableName = 'veilist_lists';
  static const int _col = 0;

  VeilidTableDB? _db;

  Future<VeilidTableDB> _open() async =>
      _db ??= await Veilid.instance.openTableDB(_tableName, 1);

  @override
  Future<List<LocalList>> loadAll() async {
    final db = await _open();
    final out = <LocalList>[];
    try {
      for (final key in await db.getKeys(_col)) {
        // a single undecryptable or malformed row (e.g. after a reinstall
        // rotated the device key) must not drop the whole roster.
        try {
          final j = await db.loadJson(_col, key);
          if (j is Map<String, dynamic>) out.add(LocalList.fromJson(j));
        } catch (e) {
          debugPrint('skipping unreadable roster entry: $e');
        }
      }
    } catch (e) {
      debugPrint('roster keys unreadable, starting empty: $e');
    }
    return out;
  }

  @override
  Future<void> save(LocalList list) async {
    final db = await _open();
    await db.storeStringJson(_col, list.recordKey, list.toJson());
  }

  @override
  Future<void> remove(String recordKey) async {
    final db = await _open();
    await db.delete(_col, utf8.encoder.convert(recordKey));
  }
}

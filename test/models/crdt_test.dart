import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veilist/models/crdt.dart';
import 'package:veilist/models/item_state.dart';

// ts helper: bigger `m` => later. `member` is the tiebreak.
LogicalTs ts(int m, [int member = 0]) => LogicalTs(m, member);

void main() {
  group('foldList', () {
    test('a single member add shows one visible item', () {
      final c = Contribution()..addItem('a', 'milk', ts(1));
      final list = foldList([c]);
      expect(list.length, 1);
      expect(list.single.text, 'milk');
      expect(list.single.state, ItemState.unstarted);
    });

    test('later ts wins on the same field', () {
      final c = Contribution()
        ..addItem('a', 'milk', ts(1))
        ..setText('a', 'oat milk', ts(5));
      expect(foldList([c]).single.text, 'oat milk');
    });

    test('concurrent edits to different fields both survive', () {
      // member 0 renames the item; member 1 marks it complete, no field overlap.
      final a = Contribution()
        ..addItem('x', 'bread', ts(1, 0))
        ..setText('x', 'sourdough', ts(3, 0));
      final b = Contribution()..setState('x', ItemState.complete, ts(2, 1));
      final item = foldList([a, b]).single;
      expect(item.text, 'sourdough');
      expect(item.state, ItemState.complete);
    });

    test('member-index breaks equal-micros ties deterministically', () {
      final a = Contribution()..addItem('x', 'from-a', ts(9, 0));
      final b = Contribution()..addItem('x', 'from-b', ts(9, 1));
      // equal micros -> higher member index wins.
      expect(foldList([a, b]).single.text, 'from-b');
    });

    test('a remove tombstones the item across the fold', () {
      final a = Contribution()..addItem('x', 'eggs', ts(1, 0));
      final b = Contribution()..removeItem('x', ts(2, 1));
      expect(foldList([a, b]), isEmpty);
    });

    test('a re-add after a remove wins when its ts is greater', () {
      final a = Contribution()..addItem('x', 'eggs', ts(1, 0));
      final b = Contribution()..removeItem('x', ts(2, 1));
      a.addItem('x', 'eggs', ts(3, 0));
      expect(foldList([a, b]).length, 1);
    });

    test('items sort by order then id', () {
      final c = Contribution()
        ..addItem('b', 'second', ts(10))
        ..addItem('a', 'first', ts(5));
      final ids = foldList([c]).map((i) => i.id).toList();
      expect(ids, ['a', 'b']); // order defaults to creation micros
    });

    test('fold is independent of contribution order', () {
      final a = Contribution()..addItem('x', 'v-a', ts(1, 0));
      final b = Contribution()..setText('x', 'v-b', ts(2, 1));
      final forward = foldList([a, b]).single.text;
      final backward = foldList([b, a]).single.text;
      expect(forward, backward);
      expect(forward, 'v-b');
    });
  });

  group('json roundtrip', () {
    test('a contribution survives encode/decode unchanged', () {
      final c = Contribution()
        ..addItem('x', 'cheese', ts(1, 2))
        ..setState('x', ItemState.blocked, ts(4, 2))
        ..addItem('y', 'wine', ts(2, 2))
        ..removeItem('y', ts(6, 2));

      final wire = jsonEncode(c.toJson());
      final back = Contribution.fromJson(
        jsonDecode(wire) as Map<String, dynamic>,
      );

      final before = foldList([c]);
      final after = foldList([back]);
      expect(after.length, before.length);
      expect(after.single.id, 'x');
      expect(after.single.state, ItemState.blocked);
    });
  });
}

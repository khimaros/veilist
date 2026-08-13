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

  group('HybridClock', () {
    test('an edit made after seeing a peer wins, however skewed our clock', () {
      // the whole point: our wall clock is an hour behind the peer's, but we
      // have SEEN their edit, so ours is causally later and must sort later.
      // under plain wall-clock ordering our edit would lose and vanish.
      final peerEdit = LogicalTs(3600 * 1000000, 1);
      final ours = HybridClock(physicalNow: () => 1000);
      ours.observe(peerEdit);
      expect(ours.now(0) > peerEdit, isTrue);
    });

    test('two edits in the same microsecond still order', () {
      final clock = HybridClock(physicalNow: () => 500);
      final first = clock.now(0);
      expect(clock.now(0) > first, isTrue);
    });

    test('the wall clock drives ordering once it moves on', () {
      var physical = 100;
      final clock = HybridClock(physicalNow: () => physical);
      final first = clock.now(0);
      physical = 200;
      final second = clock.now(0);
      expect(second > first, isTrue);
      expect(second.micros, 200);
      expect(second.counter, 0, reason: 'a fresh microsecond resets the count');
    });

    test('observing an older peer timestamp never moves us backwards', () {
      final clock = HybridClock(physicalNow: () => 5000);
      final ahead = clock.now(0);
      clock.observe(const LogicalTs(1, 9));
      expect(clock.now(0) > ahead, isTrue);
    });

    test('a timestamp round-trips, and a pre-clock one still parses', () {
      const stamped = LogicalTs(5, 1, 7);
      expect(LogicalTs.fromJson(stamped.toJson()).compareTo(stamped), 0);
      // written by a client built before hybrid clocks: two fields, no counter.
      final legacy = LogicalTs.fromJson([5, 1]);
      expect(legacy.micros, 5);
      expect(legacy.member, 1);
      expect(legacy.counter, 0);
      // and such a client reads ours as the wall-clock ts it understands.
      expect(stamped.toJson()[0], 5);
      expect(stamped.toJson()[1], 1);
    });
  });
}

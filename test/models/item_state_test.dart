import 'package:flutter_test/flutter_test.dart';
import 'package:veilist/models/item_state.dart';

void main() {
  group('ItemState', () {
    test('v1 checkbox cycle goes new -> active -> complete -> new', () {
      expect(
        ItemState.unstarted.cycleNext(among: ItemState.v1Cycle),
        ItemState.active,
      );
      expect(
        ItemState.active.cycleNext(among: ItemState.v1Cycle),
        ItemState.complete,
      );
      expect(
        ItemState.complete.cycleNext(among: ItemState.v1Cycle),
        ItemState.unstarted,
      );
    });

    test('full cycle follows canonical order and wraps', () {
      expect(ItemState.unstarted.cycleNext(), ItemState.active);
      expect(ItemState.deferred.cycleNext(), ItemState.unstarted);
    });

    test('a state outside the active subset restarts that subset', () {
      // a peer set `blocked` while our ui only cycles todo/done; clicking should
      // not get stuck on a state the subset does not contain.
      expect(
        ItemState.blocked.cycleNext(among: ItemState.v1Cycle),
        ItemState.unstarted,
      );
    });

    test('code roundtrips and is stable for the wire format', () {
      for (final s in ItemState.values) {
        expect(ItemState.fromCode(s.code), s);
      }
      // unknown codes degrade to unstarted rather than throwing.
      expect(ItemState.fromCode('bogus'), ItemState.unstarted);
    });

    test('glyphs match the plain-text notation', () {
      expect(ItemState.unstarted.glyph, ' ');
      expect(ItemState.complete.glyph, 'x');
      expect(ItemState.blocked.glyph, '!');
    });
  });
}

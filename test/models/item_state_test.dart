import 'package:flutter_test/flutter_test.dart';
import 'package:veilist/models/item_state.dart';

void main() {
  group('ItemState', () {
    test('a tap toggles between open and complete', () {
      expect(ItemState.unstarted.toggled, ItemState.complete);
      expect(ItemState.complete.toggled, ItemState.unstarted);
    });

    test('a tap completes any other state in one step', () {
      // reaching those states needs the picker, so a tap must not walk a cycle
      // through them - it ticks the item off like any other.
      for (final state in [ItemState.active, ItemState.blocked]) {
        expect(state.toggled, ItemState.complete);
      }
    });

    test('the picker offers the shipped states in canonical order', () {
      expect(ItemState.selectable, [
        ItemState.unstarted,
        ItemState.active,
        ItemState.complete,
        ItemState.blocked,
      ]);
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

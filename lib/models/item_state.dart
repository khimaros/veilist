// the state of a single list item. glyphs match the plain-text notation so a
// list reads the same in the app and as text (see REQUIREMENTS.md R7). the
// declaration order is the canonical order the picker presents.

/// item states in canonical order.
enum ItemState {
  // `code` is the stable on-the-wire identifier; never rename an existing code
  // or old dht data and share links would misread. `glyph` is the checkbox
  // character; `label` is the display text.
  unstarted('new', ' ', 'new'),
  active('active', '@', 'active'),
  complete('complete', 'x', 'complete'),
  obsolete('obsolete', '~', 'obsolete'),
  undecided('undecided', '?', 'undecided'),
  blocked('blocked', '!', 'blocked'),
  deferred('deferred', '>', 'deferred');

  const ItemState(this.code, this.glyph, this.label);

  final String code;
  final String glyph;
  final String label;

  /// the states the checkbox's press-and-hold picker offers, in canonical order
  /// (R7). the rest stay in the model and wire format, so surfacing them later
  /// touches no dht data and no links.
  static const List<ItemState> selectable = [
    unstarted,
    active,
    complete,
    blocked,
  ];

  static ItemState fromCode(String code) =>
      values.firstWhere((s) => s.code == code, orElse: () => unstarted);

  /// what a plain checkbox tap produces: ticking off and re-opening an item is
  /// the common case, so a tap only moves between those two. every other state
  /// (including one a peer set) completes on the first tap.
  ItemState get toggled => this == complete ? unstarted : complete;
}

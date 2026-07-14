// the state of a single list item. glyphs match the plain-text notation so a
// list reads the same in the app and as text (see REQUIREMENTS.md R7). the
// declaration order is also the checkbox cycle order.

/// item states in canonical cycle order.
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

  /// the states the checkbox cycles through, in order (R7). the full set stays
  /// in the model and wire format so enabling the rest later touches no data and
  /// no links.
  static const List<ItemState> v1Cycle = [unstarted, active, complete];

  static ItemState fromCode(String code) =>
      values.firstWhere((s) => s.code == code, orElse: () => unstarted);

  /// next state when the checkbox is clicked, cycling within [among] (default
  /// the full set) in canonical order and wrapping at the end.
  ItemState cycleNext({List<ItemState> among = values}) {
    final i = among.indexOf(this);
    // a state outside the active subset (e.g. a peer set `blocked` while our ui
    // only cycles todo/done) restarts the cycle rather than getting stuck.
    if (i == -1) return among.first;
    return among[(i + 1) % among.length];
  }
}

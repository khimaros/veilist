// the collaborative list crdt (see DESIGN.md "the crdt"). every member writes
// only its own contribution map; any reader folds all members' maps into the
// visible list. item fields are independent last-writer-wins registers, so one
// member toggling a state never clobbers another's concurrent text edit.

import 'item_state.dart';

/// a logical timestamp: wall-clock microseconds with a member-index tiebreak,
/// compared lexicographically. good enough for v1; a hybrid logical clock is a
/// later hardening step (see DESIGN.md).
class LogicalTs implements Comparable<LogicalTs> {
  const LogicalTs(this.micros, this.member);

  final int micros;
  final int member;

  @override
  int compareTo(LogicalTs o) => micros != o.micros
      ? micros.compareTo(o.micros)
      : member.compareTo(o.member);

  bool operator >(LogicalTs o) => compareTo(o) > 0;

  List<dynamic> toJson() => [micros, member];

  factory LogicalTs.fromJson(List<dynamic> j) =>
      LogicalTs(j[0] as int, j[1] as int);
}

/// a single last-writer-wins register: a value stamped with the ts at which it
/// was asserted. [pick] keeps whichever of two registers has the greater ts.
class Lww<T> {
  const Lww(this.value, this.ts);

  final T value;
  final LogicalTs ts;

  static Lww<T>? pick<T>(Lww<T>? a, Lww<T>? b) {
    if (a == null) return b;
    if (b == null) return a;
    return b.ts > a.ts ? b : a;
  }
}

/// one member's assertions about one item. each field is independent so
/// concurrent edits to different fields all survive the fold.
class ItemAssertion {
  ItemAssertion({this.present, this.text, this.state, this.order});

  Lww<bool>? present;
  Lww<String>? text;
  Lww<ItemState>? state;
  Lww<int>? order;

  /// merge [o] into a new assertion, taking the greater-ts value per field.
  ItemAssertion mergedWith(ItemAssertion o) => ItemAssertion(
    present: Lww.pick(present, o.present),
    text: Lww.pick(text, o.text),
    state: Lww.pick(state, o.state),
    order: Lww.pick(order, o.order),
  );

  Map<String, dynamic> toJson() => {
    if (present != null) 'p': {'v': present!.value, 't': present!.ts.toJson()},
    if (text != null) 'x': {'v': text!.value, 't': text!.ts.toJson()},
    if (state != null) 's': {'v': state!.value.code, 't': state!.ts.toJson()},
    if (order != null) 'o': {'v': order!.value, 't': order!.ts.toJson()},
  };

  factory ItemAssertion.fromJson(Map<String, dynamic> j) {
    Lww<V>? read<V>(String k, V Function(dynamic) conv) {
      final f = j[k];
      if (f == null) return null;
      return Lww<V>(conv(f['v']), LogicalTs.fromJson(f['t'] as List<dynamic>));
    }

    return ItemAssertion(
      present: read('p', (v) => v as bool),
      text: read('x', (v) => v as String),
      state: read('s', (v) => ItemState.fromCode(v as String)),
      order: read('o', (v) => v as int),
    );
  }
}

/// one member's whole contribution: a map of item id to that member's latest
/// assertions. this is the payload written to the member's dht subkey. it is
/// self-compacting - it only ever holds the latest assertion per field.
class Contribution {
  Contribution([Map<String, ItemAssertion>? items])
    : items = items ?? <String, ItemAssertion>{};

  final Map<String, ItemAssertion> items;

  ItemAssertion _at(String id) => items.putIfAbsent(id, ItemAssertion.new);

  void addItem(String id, String text, LogicalTs ts) {
    final a = _at(id)
      ..present = Lww(true, ts)
      ..text = Lww(text, ts)
      ..order = Lww(ts.micros, ts);
    a.state ??= Lww(ItemState.unstarted, ts);
  }

  void setText(String id, String text, LogicalTs ts) =>
      _at(id).text = Lww(text, ts);

  void setState(String id, ItemState state, LogicalTs ts) =>
      _at(id).state = Lww(state, ts);

  void setOrder(String id, int order, LogicalTs ts) =>
      _at(id).order = Lww(order, ts);

  void removeItem(String id, LogicalTs ts) => _at(id).present = Lww(false, ts);

  Map<String, dynamic> toJson() => items.map((k, v) => MapEntry(k, v.toJson()));

  factory Contribution.fromJson(Map<String, dynamic> j) => Contribution(
    j.map(
      (k, v) => MapEntry(k, ItemAssertion.fromJson(v as Map<String, dynamic>)),
    ),
  );
}

/// a materialized item after folding every member's contributions.
class ListItem {
  const ListItem({
    required this.id,
    required this.text,
    required this.state,
    required this.order,
  });

  final String id;
  final String text;
  final ItemState state;
  final int order;
}

/// fold every member's contribution into the visible, ordered list. pure and
/// deterministic: the same set of contributions always yields the same list,
/// regardless of merge order.
List<ListItem> foldList(Iterable<Contribution> contributions) {
  final merged = <String, ItemAssertion>{};
  for (final c in contributions) {
    c.items.forEach((id, a) {
      final cur = merged[id];
      merged[id] = cur == null ? a : cur.mergedWith(a);
    });
  }

  final items = <ListItem>[];
  merged.forEach((id, a) {
    if (a.present?.value != true) return; // absent or tombstoned
    items.add(
      ListItem(
        id: id,
        text: a.text?.value ?? '',
        state: a.state?.value ?? ItemState.unstarted,
        order: a.order?.value ?? 0,
      ),
    );
  });

  items.sort(
    (x, y) =>
        x.order != y.order ? x.order.compareTo(y.order) : x.id.compareTo(y.id),
  );
  return items;
}

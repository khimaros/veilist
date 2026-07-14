// how a list is laid out across a veilid dht record's subkeys (see DESIGN.md).
//
// the record uses a SMPL schema with oCnt=0 (no owner subkeys) and MAX_MEMBERS
// pre-allocated member slots. member i owns the subkey range
// [i*SUBKEYS_PER_MEMBER, (i+1)*SUBKEYS_PER_MEMBER); v1 writes only the first
// subkey of the range. keeping every write inside one member's own range means
// a device never has to switch writers - it writes only its own slot.

import '../models/crdt.dart';

/// pre-allocated collaborator slots per list. the SMPL schema is immutable, so
/// this is the hard cap on distinct members (see DESIGN.md limitations).
const int kMaxMembers = 16;

/// subkeys reserved per member. v1 uses the first; the rest are headroom for
/// chunking a large contribution across subkeys later.
const int kSubkeysPerMember = 2;

/// there are no owner subkeys; list metadata lives in the creator's member doc.
const int kOwnerSubkeys = 0;

/// the subkey a member writes its contribution to.
int memberDataSubkey(int memberIndex) => memberIndex * kSubkeysPerMember;

/// one member's on-the-wire payload: its item contributions plus an optional
/// list title, a last-writer-wins field any member may set. the fold takes the
/// greatest-ts title across all members.
class MemberDoc {
  MemberDoc({this.title, Contribution? contribution})
    : contribution = contribution ?? Contribution();

  Lww<String>? title;
  final Contribution contribution;

  Map<String, dynamic> toJson() => {
    if (title != null) 't': {'v': title!.value, 't': title!.ts.toJson()},
    'i': contribution.toJson(),
  };

  factory MemberDoc.fromJson(Map<String, dynamic> j) {
    final t = j['t'];
    return MemberDoc(
      title: t == null
          ? null
          : Lww<String>(t['v'] as String, LogicalTs.fromJson(t['t'] as List)),
      contribution: Contribution.fromJson(
        (j['i'] ?? const {}) as Map<String, dynamic>,
      ),
    );
  }
}

/// fold a set of member docs into the visible list title and items. the title
/// is the greatest-ts assertion across docs (in practice the creator's).
({String title, List<ListItem> items}) foldDocs(Iterable<MemberDoc> docs) {
  Lww<String>? title;
  final contributions = <Contribution>[];
  for (final d in docs) {
    title = Lww.pick(title, d.title);
    contributions.add(d.contribution);
  }
  return (title: title?.value ?? '', items: foldList(contributions));
}

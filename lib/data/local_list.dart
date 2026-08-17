// what this device remembers about one list it created or joined. persisted in
// veilid's table_db (see ListStore). the creator additionally keeps the whole
// member keypair pool and which slots it has handed out, so it can keep
// inviting distinct members across restarts.

class LocalList {
  LocalList({
    required this.recordKey,
    required this.isOwner,
    required this.writer,
    required this.memberIndex,
    required this.title,
    required this.addedAt,
    this.published = true,
    this.localDoc,
    this.republishedAt = 0,
    List<String>? memberPool,
    Set<int>? assignedSlots,
  }) : memberPool = memberPool ?? const [],
       assignedSlots = assignedSlots ?? <int>{};

  /// dht record key. for a published list this is a VLD0 typed key; a list
  /// created locally but not yet shared uses a `local:` placeholder until the
  /// first share allocates a real record.
  String recordKey;

  /// true if this device created the list.
  final bool isOwner;

  /// this device's writer keypair (VLD0:pub:secret) for its member slot. empty
  /// for a not-yet-published list; the first share allocates it.
  String writer;

  /// this device's member slot index.
  final int memberIndex;

  /// last known title, cached so the listing renders without a network read.
  String title;

  /// when this list was added locally (micros since epoch), for stable order.
  final int addedAt;

  /// false for a list created on this device that has not been shared yet: it
  /// lives only on-device (see [localDoc]) with no dht record, so nothing is
  /// published to the network until the first share (R8).
  bool published;

  /// this device's own MemberDoc json, as of its last edit. for an unpublished
  /// list it is the list's only storage; for a published one it is a copy kept
  /// alongside the dht record, so a record the network has forgotten - or a
  /// read that comes back empty - can never make this device publish an empty
  /// doc over its own contribution. null until this device has edited.
  String? localDoc;

  /// when this device last wrote its own doc to the record (micros since epoch,
  /// 0 for never). storage nodes evict records nobody writes to, so a published
  /// list is re-written periodically to keep it reachable.
  int republishedAt;

  /// creator only: every member slot's keypair, indexed by slot. empty until
  /// the list is published.
  List<String> memberPool;

  /// creator only: slots already handed out (includes the creator's own slot).
  final Set<int> assignedSlots;

  Map<String, dynamic> toJson() => {
    'recordKey': recordKey,
    'isOwner': isOwner,
    'writer': writer,
    'memberIndex': memberIndex,
    'title': title,
    'addedAt': addedAt,
    'published': published,
    if (localDoc != null) 'localDoc': localDoc,
    'republishedAt': republishedAt,
    if (isOwner) 'memberPool': memberPool,
    if (isOwner) 'assignedSlots': assignedSlots.toList(),
  };

  factory LocalList.fromJson(Map<String, dynamic> j) => LocalList(
    recordKey: j['recordKey'] as String,
    isOwner: j['isOwner'] as bool,
    writer: j['writer'] as String,
    memberIndex: j['memberIndex'] as int,
    title: j['title'] as String? ?? '',
    addedAt: j['addedAt'] as int,
    // default true so lists saved before this field existed load as published.
    published: j['published'] as bool? ?? true,
    localDoc: j['localDoc'] as String?,
    republishedAt: j['republishedAt'] as int? ?? 0,
    memberPool: (j['memberPool'] as List?)?.map((e) => e as String).toList(),
    assignedSlots: (j['assignedSlots'] as List?)?.map((e) => e as int).toSet(),
  );
}

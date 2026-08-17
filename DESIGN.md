# design

how veilist maps "a shared, collaborative list" onto veilid primitives.

## overview

veilist is a single flutter codebase targeting android, ios, linux, and web.
there is no server. every list lives as one veilid dht record. peers read and
write it directly; the web build runs veilid in the browser via wasm, so the
browser fallback is also serverless (R3, R8).

layers (see `lib/`):

- `models/` - pure data and the crdt. no veilid imports, no io. unit-testable.
- `veilid/` - `VeilidService` owns core lifecycle, attach state, the update
  stream, and a routing context.
- `data/` - `ListRepository` maps lists to dht records: create, open, watch,
  write op-logs, materialize. persists the roster via veilid table_db.
  `share_link.dart` builds and parses share links.
- `ui/` - listing page and list detail (state via `ChangeNotifier`), plus
  deep-link/url handling (`link_handler.dart`, `web_url*.dart`).

## why an operation-log crdt

the collaboration model (R4) is "everyone with the link can edit, edits are
attributable and can be ignored". veilid's multi-writer schema (SMPL) gives
each writer an exclusive range of subkeys - two writers never write the same
subkey. that rules out a single shared mutable blob and points straight at a
per-writer log that readers merge.

so each member writes only its own subkeys, and any reader folds all members'
logs into the visible list. attribution is intrinsic (a change is in exactly
one member's subkeys) and ignoring a member is just skipping their subkeys.

## dht record layout

one list = one dht record with a SMPL schema, allocated at creation:

```
DHTSchema.smpl(oCnt: 0, members: [ M_0, M_1, ... M_{N-1} ])
M_i = DHTSchemaMember(mKey: memberPubKey_i, mCnt: kSubkeysPerMember)
```

- N = `kMaxMembers` member slots, pre-allocated. the SMPL schema is immutable
  after creation, so membership capacity is fixed up front. the creator
  generates N member keypairs and keeps every secret locally.
- there are no owner subkeys (`oCnt: 0`); list metadata lives in the creator's
  member doc, not a separate owner range.
- the list **title** is a last-writer-wins field carried in each member's doc;
  the fold takes the greatest-ts title, so any member (not just the creator) can
  rename the list.
- member i owns subkeys `[i*K, (i+1)*K)` where K = `kSubkeysPerMember`. this is
  member i's **contribution map** (below). K > 1 leaves headroom to chunk a
  large map across subkeys later; v1 uses the first subkey of the range.

sharing hands a distinct unused member keypair to each invitee, so every
collaborator writes a different slot and is individually attributable and
ignorable. capacity is bounded by N; see limitations.

## the crdt (models/)

item fields are independent last-writer-wins registers, so toggling a state
never clobbers a concurrent text edit.

a member's contribution map is `itemId -> { field -> {value, ts} }` for the
fields `present` (bool), `text` (string), `state` (enum), `order` (int). this
map is already compacted: it only ever holds each writer's latest assertion per
field, so it stays O(items the member touched) and fits one subkey.

`ts` is a **hybrid logical timestamp**: `(wallClockMicros, counter,
memberIndex)`, compared lexicographically in that order. plain wall-clock
last-writer-wins would make conflict resolution depend on the devices' clocks
agreeing - an edit made after seeing a peer's change loses whenever the peer's
clock runs ahead - so each device keeps a `HybridClock` that advances past every
timestamp it observes from another member. an edit that could have seen a peer's
edit therefore always carries a greater ts, whatever the skew. edits that are
genuinely concurrent (neither side had seen the other) fall through to the
counter and then the member index: an arbitrary but deterministic order, which
is all any scheme can offer without synchronised clocks. the clock ratchets, so
one peer with a wildly fast clock pulls every device that reads its edits
forward with it.

on the wire the counter is appended - `[micros, member, counter]` - so a client
built before hybrid clocks reads the first two fields as it always did and
ignores the third, degrading to wall-clock ordering rather than misparsing.

a reader **merges** each member's doc into the copy it already holds rather than
replacing it (`MemberDoc.mergedWith`, per-field greatest ts). a dht read is
answered by whichever replica responds, so it can return an older version of a
subkey; replacing would step that member's contribution backwards and the view
would visibly bounce between states as reads alternated. merging makes a view
monotonic: it only ever moves forward.

**fold** (deterministic, pure): merge all members' maps; for each item id and
field pick the assertion with the greatest `ts`. an item is visible iff its
latest `present` is true. its text/state/order come from the latest of each.
items sort by `(order, id)`.

editing = update the field's register in *this device's* map with a fresh ts,
then write the map to this member's subkey.

## item states (R7)

`ItemState` is an enum whose glyphs match the plain-text notation:
`[ ]` new, `[@]` active, `[x]` complete, `[~]` obsolete, `[?]` undecided,
`[!]` blocked, `[>]` deferred. ticking an item off is by far the common case, so
a checkbox tap only moves between complete and new (`toggled`); every other
state is a deliberate choice, made by pressing and holding the item - anywhere
on the row, not just the checkbox - and picking from `ItemState.selectable`
(new, active, complete, blocked). the
remaining states stay in the enum and wire format, so surfacing them later
touches no dht data and no links (R7).

## sharing and links (R1, R2, R3)

a share link carries the record key and one member keypair:

```
app:  veilist://l/<recordKey>?w=<memberKeypair>&m=<memberIndex>
web:  https://<host>/#/l/<recordKey>?w=<memberKeypair>&m=<memberIndex>
```

the web form keeps the capability in the url fragment so it never reaches the
static host. on a device with the app registered for the https host, the os
opens the app (R2); otherwise the browser loads the flutter web build, which
runs veilid in wasm, reads the list, and offers "open in app" (R3). `recordKey`
is a `VLD0:` typed key; `w` is the invitee's writer keypair; `m` is the member
slot it occupies, so the joiner writes the right subkey without inspecting the
schema.

the share dialog renders the app link as a qr code, and the listing offers a
camera scanner (`ui/scan_page.dart`) that reads one back, so joining a list can
be a point-and-shoot rather than a copy-paste. camera capture has no
standard-library route, so `qr_code_dart_scan` is the one plugin here (R10): it
drives the flutter camera plugin and decodes in *pure dart* (a zxing port). the
obvious alternative, mobile_scanner, decodes with google's ml kit, which ships
closed-source blobs (`libbarhopper_v3.so`, tflite models) in the apk - barred
from f-droid and izzyondroid, so it is barred here (DISTRIBUTION.md). the
browser cannot stream camera frames to dart, so web scans a still the user
captures while native decodes the live preview. the affordance appears only
where a camera exists (android/ios/web); a refused or absent camera - including
a page served over plain http, where the browser withholds it - lands on the "no
camera available" state, with pasting still open. the production web deployment
is http (see share links, below), so scanning there needs an https origin.

opening a launch link shows a loading screen rather than the listing: `main`
resolves the link (`LinkHandler.initialLink`) before starting the node, covers
the app with a spinner (`MaterialApp.builder`) while the node attaches and the
join runs, then pushes the detail page with a zero-duration transition and drops
the cover - so an incoming shared list goes loading -> list without the listing
flashing behind it. a normal launch drops the cover as soon as boot finds no
link and shows the listing immediately while the node connects (local-first).

## persistence

the roster of known lists is stored with veilid's own `openTableDB` (no extra
storage dependency, R10). per list we persist role (owner or member), this
device's writer keypair, this device's own member doc, and - for the creator -
the full member keypair pool and which slots have been handed out, so the
creator can keep inviting across restarts. `loadAll` tolerates a single
unreadable row (e.g. one whose device encryption key was rotated by a reinstall)
rather than dropping the whole roster.

`LocalList.localDoc` holds this device's own `MemberDoc` for every list, not
only unshared ones. `OpenList` writes it before each network write and seeds it
into the fold at open. that is what makes the dht record store not the only copy
of our own contribution (R16): see "losing a member doc" below for what it
costs when it is.

## local until share (R8, R12)

a list created on this device is not published to the dht until it is first
shared. `createList` does no network work: it writes an owner `MemberDoc` (title
only) into `LocalList.localDoc`, under a `local:` placeholder key, and marks the
list `published: false`. an unpublished list is opened with a `LocalListNetwork`
- a `ListNetwork` whose reads/writes hit that on-device doc and never touch
veilid - so creating and editing are instant and leave no network footprint. the
sync chip reads "saved on this device".

the first `shareList` publishes: it creates the real record, writes the
accumulated doc to slot 0, keeps that doc in `localDoc`, and swaps the
placeholder key for the record key, setting `published: true`. because
publishing always writes slot 0, a published record always holds at least one
member doc - which is why a read that comes back with nothing is treated as a
failed read rather than an empty list. the open detail page listens to the repository and, on that
transition, rebuilds its `OpenList` so it switches from the local network to the
dht one and begins syncing. joined lists are always published.

## web / wasm (R3, R8)

the veilid rust core is compiled to `veilid_flutter_bg.wasm` +
`veilid_flutter.js` (via the veilid repo's `wasm_build.sh`) and placed under
`web/wasm/`. the flutter web build loads it and runs a full veilid node in the
page, so the browser talks to the dht directly with no gateway. routing uses
url fragments so share links resolve client-side. a link pasted into an
already-open tab changes only the fragment, which neither flutter nor app_links
reports, so `web_url_web.dart` listens for `hashchange` (pure `dart:js_interop`)
and feeds the new url to the link handler.

loading the wasm node takes a moment, so `web/index.html` paints a dark
background inline on `<html>`/`<body>` (before any css parses, to avoid a white
flash) and shows a spinner splash that reports engine/node progress; the flutter
app removes it once it paints.

## native builds (android/linux)

the veilid rust core is cross-compiled into the app during the flutter build:
android drives cargo through the rust-android gradle plugin, linux through
corrosion in the plugin's `linux/rust.cmake`. that cmake locates the crate by
walking up to the veilid monorepo root (`git rev-parse`), which only works when
the plugin is built inside a veilid checkout. consumed as an external pub/git
dependency the path is wrong, and in ci a "dubious ownership" git refusal makes
the empty result abort cmake. veilid ships no supported path for external linux
desktop builds (the same code is on veilid main), so `make deps` (and the ci
linux job) run `scripts/patch_veilid_linux.sh` after every `flutter pub get` to
point corrosion at the plugin's own bundled crate. android is unaffected (a
different build path), as is web (the wasm blob).

the android toolchain is pinned to AGP 8.9.1 + gradle 8.11.1: rust-android-gradle
0.9.6 (which veilid's plugin uses) relies on a gradle api that gradle 9 removed,
so the whole 9.x line is out, while the camerax the scanner pulls in refuses to
build below AGP 8.9.1 - the pin is the narrow band that satisfies both.

release apks are signed with a persistent key (from `android/key.properties` or
`VEILIST_KEYSTORE*` in ci) rather than the debug key, and the app's version comes
only from `pubspec.yaml`. both exist so a release can be reproduced from its tag
and updated in place; see DISTRIBUTION.md.

`scripts/build_icons.sh` renders every platform icon (android mipmaps, ios
appiconset, web) from the two svg sources in `assets/icon/`, so the icon is
edited in one place rather than as fifteen pngs.

## surviving a network change

a phone loses signal, leaves airplane mode, or moves between wifi and mobile
data, and the os takes every interface away and hands back new ones. veilid does
not reliably rebuild its network state when that happens: the node stays
attached but cannot reach anything, flaps online/offline for a few seconds, and
then sits bootstrapping forever. measured on an emulator, it never recovered -
the edits queued while it was gone stayed queued, and only restarting the app
brought it back.

so `VeilidService` runs a watchdog. if the node is unusable for `_kStuckAfter`
while we mean to be online, it calls veilid's `debug("network restart")`, which
rebuilds interfaces and sockets with the node still attached, so open records
and their watches survive. it retries no more than every `_kRecoveryRetry`, each
attempt bounded by `_kRecoveryTimeout`, and logs every attempt.

a detach/attach is the wrong tool for this and was tried first: `detach()` does
not return while the network is in this state, so the re-attach never happens,
and it would drop every open record. the watchdog is gated on `_wantOnline`, so
a deliberate detach (the e2e harness's offline hook) is never undone.

## opening a record as a joiner

`createDHTRecord` is local-only, and the creator's `setDHTValue` calls publish
the record and its subkeys to the network. a joiner opening the record for the
first time has never seen it, so `openDHTRecord` must do a network inspect,
which returns the retryable `TryAgain` until the record is reachable.
`VeilidListNetwork.openRecord` therefore retries on `TryAgain`; without it a
joiner opens with zero members and reads nothing. reads (`getDHTValue`) tolerate
`TryAgain` per subkey and are re-tried on the next refresh.

a joiner also starts read-only, but only the first time. a plain open sees only
locally-populated subkeys, so a *first-ever* join would render empty and invite
edits the real data then overwrites. `OpenList` tracks two flags:
`_loadedFromCache` (the open-time local read or the stored `localDoc` returned
data, i.e. this list synced before) and `_liveSynced` (a network read or watch
change has landed this session). `canEdit` needs one of those AND
`_mineResolved` - see "losing a member doc" - so a re-opened list loads from
cache and is editable immediately while it revalidates, and only a first-ever
join with nothing cached waits. until the live read confirms, the sync chip
reads "syncing"; `awaitingInitialSync` (the detail-body spinner) covers any list
that has nothing to show and cannot yet be edited.

### losing a member doc

each write publishes the WHOLE of this device's member doc, so a doc we have not
loaded is a doc we must not write: the snapshot would carry only the newest
edit, and since an absent assertion is not a tombstone (the fold drops any item
with no `present`), everything this device ever contributed would cease to exist
for every member - permanently, since we are our slot's only writer and
`refresh` does not merge our own slot back. this is how a real list was emptied
on two devices at once (ROADMAP phase 25).

so `OpenList` will not write until `_mineResolved`: either it holds the doc
already published in the slot (from `localDoc`, the open-time read, or a watch
change) or a read it can trust says the slot is empty. "trust" excludes a read
that returned no docs at all, however complete the layer below believed it was.

## staying in sync while open and in the roster

the watch only delivers changes that arrive *live*. a change a peer made while
this client was closed or offline is otherwise missed, because the one-shot
open-time read runs before the node has attached (isReady false) and never
retries. so `OpenList` resyncs when `ListNetwork.readiness` fires (the node
reconnected) and its periodic tick keeps calling `refresh()` until the first
live read lands.

a live watch update usually carries the changed member's new doc inline, but
veilid coalesces several subkey changes made within one flush window (two members
editing at once) into a single value-change with no inline value, expecting the
reader to re-read. `VeilidListNetwork.changes` fetches the changed subkeys in
that case rather than dropping the update; dropping it left a concurrent edit
(e.g. one member marking an item active while another edited) invisible until
veilid's ~30s fallback change-inspection.

a read can also come back *incomplete*: veilid's network inspect returns
TryAgain until a freshly opened record is reachable (the layer then falls back to
the local view of which subkeys hold data), and each subkey read can fail on its
own. `readDocs` therefore returns `(docs, complete)`, and `OpenList` treats only
a complete read as a live sync. `complete` means the network answered AND knew
about every subkey this node does; a network missing one we hold is serving a
fragment, and an answer of nothing at all is not a sync however cleanly it came
back. the read itself covers the union of both views, so a record the network
has forgotten still reads back from this node instead of coming back empty. without that distinction a joiner declared
itself synced on the first fragment and then visibly rewrote the list as the
remaining members' docs arrived - which reads as the app replaying history, when
it is really the fold gaining one member at a time. a first-ever join also keeps
its spinner until a complete read, so a scanned link never lands on a half-built
list.

writes go out one at a time. veilid stamps a write with the sequence number of
the value the writer held when the write *started*, and the dht keeps the first
value it receives at a given sequence - so two overlapping writes to one subkey
both go out at the same sequence and the later one is discarded, however much
newer, with no error and no retry. three quick taps did exactly that. `_flush`
therefore keeps a single write loop: an edit made while a write is in flight
sets a flag instead of starting its own write, and the loop re-sends the doc
when the current write lands. coalescing is safe because each write carries the
whole member doc, so the latest send subsumes every skipped one. for the same
reason `OpenList.dispose` defers `closeRecord` until that loop drains: a write
issued after the record closes is rejected outright, and leaving a list straight
after an edit is ordinary use.

the same staleness applies to lists you have not opened. while the app is
foregrounded, `ListRepository` keeps one watch per roster list (via
`startForegroundSync`): a change marks a list dirty and the repository re-reads
just that list, refreshing its cached title and warming the local store so the
next open is instant and current. veilid keys `opened_records` by record with no
refcount - a second open overwrites the entry and a single close cancels the
watch - so `VeilidListNetwork` refcounts open/close itself, letting the
foreground sync and an open detail page watch the same record without one
tearing down the other. the watch set is capped (`kMaxForegroundWatches`) to
stay under veilid's per-node open-record limit; lists beyond the cap still sync
when opened.

### keeping a record on the network

a dht record is not stored forever. the nodes holding it keep other people's
records under an lru capped at `remote_max_records` (128 a node off-web), so a
record nobody writes to is eventually evicted from every node that had it. each
member still holds its own copy, but they can no longer reach each other: reads
find nothing, and no edit either side makes ever arrives.

nothing else refreshes a record, so the foreground sync re-writes this device's
own doc every `kRepublishInterval` (6h). it is skipped while the list is open,
because a republish racing that list's own write would put two writes on one
subkey at the same sequence and the dht would silently keep only the first.

## testing

the network and store sit behind the `ListNetwork` and `ListStore` interfaces,
so the whole app runs headlessly against in-memory fakes. a single shared fake
dht lets one test play multiple actors, which is how alice/bob convergence is
proven deterministically without a network. the matrix's web frontend (python +
playwright against the real chrome, `make test-e2e`) then confirms the same
behaviour over the live veilid dht running in wasm, driven through a
`window.veilistTest` hook that exists only in e2e builds. see CONTRIBUTING.md for
the layers.

the true-ui layer (`test/e2e/appium/`, python + appium flutter-driver) drives the
real widgets on android emulators, with no test hook and no fakes, so it
exercises the app exactly as a person does. single-device tests cover every
local-first flow (create, open without an endless spinner, add, set state,
edit, reorder, swipe-delete, share dialog with qr, open-link, delete from
listing); a two-device test boots two emulators and proves deep-link join plus
bidirectional convergence over the live dht. the driven build uses
`test/driver/app.dart`, which calls `enableFlutterDriverExtension()` before any
binding exists (otherwise the driver binding assertion fails and appium cannot
attach). flutter paints to a canvas, so locators are widget keys/types/text via
the driver extension, not a native view tree. see test/scripts/appium_e2e_run.sh.

the driver extension only exists in debug/profile builds, so the appium suite
cannot run against a release apk - which means release-only startup failures are
invisible to it. the veilid protected store is one such case: its keystore-backed
secure storage fails to initialize in a release build, so startup must allow a
file-storage fallback (`protectedStore.allowInsecureFallback`). a separate
release smoke test (`make test-release-smoke`) builds a real release apk, launches
it on an emulator, and fails if veilid cannot start - closing that gap.

the compliance matrix (`test/e2e/matrix/`, `make test-compliance`) is the single
cross-platform compliance suite: one set of flows (`flows.py`) written against a
`Frontend` action abstraction and run against linux, android, and web by one
driver that prints a frontend x flow matrix. because every frontend runs the
*same* flow code, the platforms cannot drift - which is how a share-modal
regression that only manifested on the linux desktop is caught rather than
shipped. linux drives the app over its vm service (`flutter_vm.py`) on a private
headless display, android reuses the appium emulator/driver infrastructure
(`test/e2e/appium/flutter_ui.py`), and web drives the served build through the
`window.veilistTest` hook (flutter web renders to a canvas, so there is no view
tree). a flow a frontend cannot perform (a ui-only gesture on web) reports skip.

## limitations (tracked in ROADMAP "later")

- membership capacity is fixed at `kMaxMembers` per list (immutable schema).
- only the creator holds unassigned slots, so only the creator can invite new
  *distinct* members; a non-creator who re-shares shares their own slot (edits
  then co-attribute to that slot).
- last-writer-wins is per field, not a full text-merge crdt.

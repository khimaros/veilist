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

`ts` is a logical timestamp: `(wallClockMicros, memberIndex)`, compared
lexicographically. wall clock plus a member-index tiebreak is enough for v1;
a hybrid logical clock is a later hardening step.

**fold** (deterministic, pure): merge all members' maps; for each item id and
field pick the assertion with the greatest `ts`. an item is visible iff its
latest `present` is true. its text/state/order come from the latest of each.
items sort by `(order, id)`.

editing = update the field's register in *this device's* map with a fresh ts,
then write the map to this member's subkey.

## item states (R7)

`ItemState` is an enum whose glyphs match the plain-text notation:
`[ ]` new, `[@]` active, `[x]` complete, `[~]` obsolete, `[?]` undecided,
`[!]` blocked, `[>]` deferred. `cycleNext()` defines the checkbox order. v1 ui
exposes only new and complete; the enum and wire format already carry the rest,
so enabling them later touches no dht data and no links (R7).

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

## persistence

the roster of known lists is stored with veilid's own `openTableDB` (no extra
storage dependency, R10). per list we persist role (owner or member), this
device's writer keypair, and - for the creator - the full member keypair pool
and which slots have been handed out, so the creator can keep inviting across
restarts. `loadAll` tolerates a single unreadable row (e.g. one whose device
encryption key was rotated by a reinstall) rather than dropping the whole roster.

## local until share (R8, R12)

a list created on this device is not published to the dht until it is first
shared. `createList` does no network work: it writes an owner `MemberDoc` (title
only) into `LocalList.localDoc`, under a `local:` placeholder key, and marks the
list `published: false`. an unpublished list is opened with a `LocalListNetwork`
- a `ListNetwork` whose reads/writes hit that on-device doc and never touch
veilid - so creating and editing are instant and leave no network footprint. the
sync chip reads "saved on this device".

the first `shareList` publishes: it creates the real record, writes the
accumulated doc to slot 0, swaps the placeholder key for the record key, and sets
`published: true`. the open detail page listens to the repository and, on that
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
`_loadedFromCache` (the open-time local read returned data, i.e. this list
synced before) and `_liveSynced` (a network read or watch change has landed this
session). `canEdit` is true for a list you created, or once either flag is set -
so a re-opened list loads from cache and is editable immediately while it
revalidates, and only a first-ever join with nothing cached waits. until the
live read confirms, the sync chip reads "syncing"; `awaitingInitialSync` (the
detail-body spinner) is shown only for that first-ever, nothing-cached case.

## staying in sync while open and in the roster

the watch only delivers changes that arrive *live*. a change a peer made while
this client was closed or offline is otherwise missed, because the one-shot
open-time read runs before the node has attached (isReady false) and never
retries. so `OpenList` resyncs when `ListNetwork.readiness` fires (the node
reconnected) and its periodic tick keeps calling `refresh()` until the first
live read lands.

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
local-first flow (create, open without an endless spinner, add, cycle state,
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

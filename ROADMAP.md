# roadmap

phased plan. each phase leaves the tree building and, once there is something
to exercise, testable. requirement ids (Rn) refer to REQUIREMENTS.md.

## phase 0 - scaffold and docs (done)

- [x] flutter project (android, ios, web, linux)
- [x] pin toolchains in mise.toml (flutter, rust)
- [x] pin veilid dependency to a released tag (R9)
- [x] Makefile: build, precommit, test-e2e
- [x] docs: REQUIREMENTS, ROADMAP, DESIGN, README, CONTRIBUTING
- [x] `make build` green for the web target

## phase 1 - veilid lifecycle (done)

- [x] initialize veilid core (ffi on native, wasm on web)
- [x] startup + attach, with a default bootstrap config
- [x] process the VeilidUpdate stream; surface attach/network state in the ui
- [x] persist app data via veilid table_db (no extra storage dep, R10)

## phase 2 - list model and crdt (done)

- [x] item state enum + cycle order (R7)
- [x] per-member self-compacting contribution map (add/setState/setText/remove/order)
- [x] deterministic fold to a materialized list (per-field last-writer-wins, R4)
- [x] json serialization; pure functions covered by tests

## phase 3 - local list management and listing page (done)

- [x] listing page tracking all created/opened lists (R5)
- [x] create list, open list detail, delete a list, share a list (R6)
- [x] persist the roster of known lists in table_db

## phase 4 - dht integration (done)

- [x] create SMPL multi-writer record with pre-allocated member slots
- [x] write a member's contribution to its subkey (behind a ListNetwork iface)
- [x] open + watch remote records; re-fold live on value changes (R4)

## phase 5 - sharing and deep links (done)

- [x] build share links (veilist:// scheme + https web fragment) carrying the
      record key and an unused member keypair (R1)
- [x] handle incoming links: open/join a list as a distinct writer (R2, R4)
- [x] add joined lists to the listing page (R5)
- [x] register the veilist:// scheme on android + ios so links open the app

## phase 6 - web target (done)

- [x] compile the veilid wasm blob and wire it into web/ (R8; scripts/build_wasm.sh)
- [x] flutter web build boots veilid in the browser (index.html bootstrap)
- [x] share links resolve client-side via url fragment (R3)

## testing (prioritized alongside app implementation) (done)

- [x] flutter widget tests: listing + detail pages against a fake repository
- [x] logic e2e (fake dht): alice shares -> bob joins -> concurrent edits
      converge; last-writer-wins on a shared field
- [x] unit tests: share-link build/parse, item-state cycle, member-doc fold

## phase 7 - end-to-end tests (done)

- [x] python (uv) + playwright harness driving the system chrome; `make test-e2e`
- [x] browser e2e: the web build boots and a real veilid node attaches to the
      public network inside chrome via wasm (R3, R8)
- [x] two independent veilid nodes start in one browser (multi-actor substrate)
- [x] multi-actor alice/bob over the live dht: alice shares -> bob joins ->
      alice's item reaches bob -> bob completes it -> alice converges. driven
      through a gated test hook; xfails (not fails) if the network is unavailable

## phase 8 - android build + two-device emulator e2e

- [x] android build works: native veilid lib for arm64/arm/x86_64 (AGP 8.7 +
      gradle 8.9 for the veilid rust-android plugin; ANDROID_HOME for build.rs)
- [x] emulator toolchain via mise: emulator + api-35 x86_64 image + avds
      (`make android-e2e-setup`)
- [x] veilid ipv4-only on emulators (slirp site-local ipv6 is misdetected as
      global and stalls bootstrap)
- [x] retry openDHTRecord on TryAgain: a fresh joiner's network open returns
      TryAgain until the record is reachable; without retry it read zero members
- [x] two concurrent emulators (alice + bob), gradle builds staggered so they
      do not overlap; adb-safe orchestration
- [x] two-device alice/bob over the live dht on two emulators: alice shares,
      bob reads her item and completes it, alice reads the completion back -
      converges both ways (now driven from the ui by `make test-ui-e2e-two`,
      see phase 9)

## phase 9 - true ui end-to-end (appium flutter-driver, python)

drives the real widgets on the emulator instead of the repository, so the tests
exercise every user story exactly as a person would. python/uv, one appium home
under test/e2e/appium/.appium. see test/scripts/appium_e2e_run.sh and
`make test-ui-e2e`.

- [x] fix test_driver entrypoint: call enableFlutterDriverExtension() before any
      binding exists (WidgetsFlutterBinding.ensureInitialized first made it
      assert, so ext.flutter.driver never registered and appium could not attach)
- [x] fix the share dialog rendering as an empty overlay: AlertDialog queried
      the content's intrinsic width, which crashed on _CopyRow's Expanded; bound
      the width and make it scroll
- [x] single-device flows: create/track (R5,R12), open with no infinite spinner
      (R12), add + cycle state (R7), edit text + reorder + swipe-delete (R11),
      connection + sync status (R13), share dialog with qr and both links (R1),
      open-link validation (R2), delete from listing (R6)
- [x] two-device: alice shares -> bob opens the deep link -> edits converge both
      ways, over the live dht on two emulators (R1,R2,R4); this python suite
      replaced the dart integration_test, so e2e is now all python
- [x] fix release-only startup crash: the keystore-backed veilid protected store
      fails to initialize in release builds ("could not initialize the protected
      store"); allow a file-storage fallback (protectedStore.allowInsecureFallback)
- [x] release smoke test (`make test-release-smoke`): appium flutter-driver only
      attaches to debug/profile builds, so release-only failures like the above
      slipped past the ui e2e; this builds a real release apk and fails if veilid
      cannot start

## phase 10 - cross-platform compliance suite

the same user flows (`test/e2e/matrix/flows.py`) run against every supported
platform via the flutter driver extension - the one locator surface that works
on a canvas-rendered ui everywhere. `make test-compliance`.

- [x] python flutter-driver client over the dart vm service (`flutter_vm.py`),
      so linux/web are driven directly (appium wraps the same protocol on
      android)
- [x] shared scenarios: the nine single-device flows, one code path per platform
- [x] linux runner: launches the desktop app on a private headless display
      (xvfb + x11 backend, so it never fights a wayland desktop), fresh app per
      flow for determinism; 9/9 green
- [x] fix release-only linux share modal via a rebuild (the crash was fixed
      earlier but the running binary predated it); the suite now guards it
- [x] android runs the shared compliance flows: e2e-appium/test_compliance_flows.py
      runs scenarios.ALL through the existing appium flutter-driver emulator
      infrastructure (flutter_ui adapter gained settle/home), so android
      exercises the same flows as linux without duplicating them
- [x] compliance matrix (e2e-matrix/): one set of flows written against a
      Frontend action abstraction, run against every frontend by a single driver
      that prints a frontend x flow matrix. the frontends cannot drift because
      they run the same flow code. linux (flutter_vm), android (appium
      flutter_ui), web (playwright + expanded window.veilistTest hook - not the
      flutter driver, since web renders to a canvas). ui-only flows report skip.
- [x] BUG (found via the matrix): refresh() overwrote our own member slot with
      the network copy, clobbering an in-flight local edit (e.g. a rename racing
      the open-time refresh). fixed: refresh() skips our own slot, like the watch
      already did. covered by list_repository_test.dart.
- [x] BUG (found via the android matrix): foreground sync's _syncAll iterated
      _lists.take(...) (a live view) with awaits between entries; a concurrent
      roster mutation (a share re-key, or another readiness-triggered sync -
      android emits several attachment transitions, each re-running _syncAll)
      threw "concurrent modification", the unhandled error broke the widget tree,
      and the share dialog never rendered (share passed on linux/web, which did
      not hit the race). fixed: iterate a snapshot. covered by
      list_repository_test.dart.
- [x] all three frontends green in the matrix: linux 18/18, web 17/18 + 1 skip
      (hide-completed is ui-only via the hook), android 13/13 single-device
      (collaboration skips without a second emulator). android needed frame sync
      disabled: the "publishing..." share spinner animates forever and appium's
      waitFor blocks on an unsettled frame (flutter_vm disables it, so linux/web
      were unaffected). android flows also wait for veilid online before running
      so a share can publish.

## phase 11 - production polish

- [x] fix "AlreadyInitialized" on a deep link while the app is open: MainActivity
      is singleTask (no empty taskAffinity) so a veilist:// intent reuses the
      running engine instead of spawning a second one that re-inits veilid
- [x] add-item field keeps focus after enter, and rides above the keyboard (moved
      into the body column, not the bottomNavigationBar)
- [x] resync on resume: the detail page force-refreshes on
      AppLifecycleState.resumed, catching edits others made while it was
      backgrounded (the watch only delivers changes that arrive live)
- [x] production web url http://veilid.tech/list (http, not https: veilid's wasm
      dials bootstrap over ws://, which an https page cannot open); static build
      staged in build/web/ (server must send COOP/COEP headers)
- [x] compliance tests isolate app state in a throwaway XDG dir, so they never
      touch the user's real ~/.local/share/com.khimaros.veilist data
- [x] compliance collaboration tests: two linux instances share a list; edits
      converge both ways and last-writer-wins resolves a shared-field conflict
- [x] web: open a share link pasted into an already-open tab; flutter and
      app_links miss in-page hash changes, so a hashchange listener (pure
      dart:js_interop, no new package) feeds the url to the link handler (R2)
- [x] connected vs synchronized: a joined list is read-only until its first
      network read lands (OpenList.canEdit), so a paste recipient never edits an
      empty list that the real data then overwrites; the sync chip shows
      "syncing" until then and the detail body shows a spinner
- [x] default material accent matches the linux desktop accent (gnome blue
      #3584e4)
- [x] web loading splash: dark background baked into index.html (inline on
      <html>/<body> so it paints before any css or flutter loads) plus a spinner
      that reports engine/veilid-node progress and is removed once the app paints

## phase 12 - continuous sync and item visibility

- [x] BUG: a change a peer makes while this client is closed did not appear on
      reopen. refresh() ran only once in open() and again on resume; on a cold
      start the veilid node is still attaching (isReady false) when the list
      opens, so that read returned nothing new and nothing retried once the node
      attached. fixed: OpenList resyncs when the network becomes ready and the
      periodic tick keeps retrying until the first live read lands. (reported:
      reorder on web synced to mobile but not to the owner's linux client on
      reopen.) covered by open_list_sync_test.dart.
- [x] shared lists load from the local cache immediately and stay editable
      (OpenList.canEdit via _loadedFromCache), showing "syncing" until the live
      read confirms; only a first-ever join (nothing cached) stays read-only
      until the initial sync lands
- [x] keep every list in the roster synchronized while the app is foregrounded:
      the repository watches one record per list (refcounted opens in the
      network layer, since veilid does not refcount) and resyncs each list a
      peer changes; wired to the app lifecycle in main.dart
- [x] compliance: a member's reorder converges to another participant; a reorder
      made while a participant is closed appears when it reopens; and a rename
      reaches another member's listing (test_collaboration.py)
- [x] hide/show completed items toggle (per-session view filter; reordering is
      disabled while hiding so visible and full indices cannot diverge)
- [x] rename by tapping the app-bar title (plain text, no pencil) or from the
      listing context menu; the edit button is gone; renames propagate to other
      clients' listing. any member can rename a shared list, not just the owner:
      the title is a last-writer-wins field (was owner-only), gated on canEdit
- [x] active state added to the checkbox cycle (new -> active -> complete), R7
- [x] local until share (R8, R12): a created list lives only on-device (no dht
      record, sync chip reads "saved on this device") and is instant + editable;
      the first share publishes it to a real record and the open detail page
      swaps its local network for the dht one
- [x] roster load tolerates a bad/undecryptable row instead of dropping every
      list (a reinstall that rotates the device key no longer needs to)
- [x] docs sync: reconcile DESIGN/README/ROADMAP with the code after phase 12 -
      dht layout (oCnt=0, subkey ranges, kMaxMembers/kSubkeysPerMember naming),
      share links carry the member index (m=), fold sort is (order, id), the
      checkbox cycles new/active/complete, and the layer map drops the phantom
      routing/ dir; also marked phase 1 done
- [x] the compliance matrix (`e2e-matrix/`) is now the single cross-platform
      compliance suite, run by `make test-compliance` across linux/android/web.
      the parallel `e2e-compliance/` pytest suite and the android appium
      duplicate (`test_compliance_flows.py`) were retired; the one flow unique to
      them (a rename reaching a peer's listing via foreground sync) moved into
      `flows.py`, and `flutter_vm.py` moved into `e2e-matrix/`
- [x] the browser e2e (`e2e/`) folded into the matrix too: it was the same
      veilid-in-wasm boot + live alice/bob convergence the matrix web frontend
      already runs, so `e2e/` was retired and `make test-e2e` now runs the
      matrix's web column (`test/scripts/matrix_run.sh web`). note: the matrix
      hard-fails a collab flow that cannot reach the dht, where `e2e/` xfailed
- [x] item swipe-delete (R11) migrated into the matrix (web hook `removeItem` and
      a shared `delete_item` flow), closing the one flow the appium suite covered
      that the matrix lacked
- [x] android matrix boots two emulators so the collaboration flows run instead
      of skipping; fixed two harness bugs the two-emulator path exposed (peer and
      restart sessions must force-stop the app, not just quit the driver session)
- [x] the e2e web build writes to `build/web-e2e` (separate from the deployable
      `build/web`), so a test run never leaves the veilistTest backdoor + wrong
      base-href in the production output
- [x] moved every test definition under `test/`: the python suites to
      `test/e2e/{matrix,appium}`, the driver entrypoint to `test/driver/app.dart`,
      and the test scripts to `test/scripts/` (build scripts stay in `scripts/`)

## phase 13 - live state/rename sync

- [x] BUG: concurrent edits by two members did not propagate live. veilid
      coalesces subkey changes made within one ~1s flush window into a single
      value-change that carries no inline value (it expects a re-read);
      `VeilidListNetwork._toChanges` dropped those, so a peer's edit was invisible
      until veilid's ~30s fallback inspection - felt as "marking an item active
      did not reach the other party, but a reorder (done while only one side
      wrote) did". fixed: `_toChanges` now fetches the changed subkeys via
      `getDHTValue` when the notification has no inline value. found and locked in
      with real-veilid matrix flows: `member_state_change_converges` (R7),
      `member_item_rename_converges` (R11), and `concurrent_member_edits_converge`
      (fires both members' writes simultaneously so they coalesce), plus an
      `item_state` observable across every frontend (web reads the folded state
      via the hook; the widget frontends read the checkbox glyph via the driver).
      the concurrent flow failed ~50% of runs before the fix and 0/many after;
      full linux matrix green.
- note: the web frontend could not reproduce this - its `window.veilistTest`
      hook awaits each write, serializing them so they never coalesce - so
      `make test-e2e` now runs the true-ui linux column instead of the web column.

## phase 14 - offline write durability

- [x] a device with pending offline edits must keep trying to sync them until
      fully flushed, on any screen and while backgrounded. finding: no app bug -
      veilid's offline_subkey_writes task flushes queued writes for every record
      with pending writes whenever the node is online, the app never shuts the
      node down, and on reconnect the node reattaches in ~6s and clears pending
      writes (probed via the sync chip on linux). the OS-level android flow
      `offline_edits_flush_while_backgrounded` PASSES: real airplane-mode network
      loss + HOME backgrounding, edits still flush to a peer on reconnect.
      SUPERSEDED by phase 24: that pass was an accident of the write collision
      fixed in phase 23 (the edits escaped live while the radio was still going
      down, so nothing flushed from the background). a backgrounded app cannot
      reach the network at all, and the flow is now
      `offline_edits_flush_when_reopened`.
- [x] harness: `VeilidService.setOnline` (detach/attach) exposed via the web hook
      and a flutter-driver requestData handler (test/driver/app.dart) for
      linux/web; android uses OS-level adb (airplane-mode, HOME) instead - no
      in-app backdoor. flows `offline_edits_flush_on_reconnect` (listing) and
      `offline_edits_flush_when_reopened`.
- note: detach/attach is an UNFAITHFUL offline primitive - it fully drops the
      node so `attach()` triggers a slow re-bootstrap and a peer misses the last
      edit within the window (the node itself recovers fine). OS-level network
      loss (android airplane-mode, phase 15) is the faithful test; the linux/web
      detach/attach flows are kept only as a rough proxy.
- [ ] `offline_edits_flush_on_reconnect` is flaky on android (the peer sometimes
      misses the final rapid offline edit within 120s while the backgrounded
      variant passes). harden: after go_offline, confirm the node is actually
      offline before editing (so every edit is truly queued), settle after the
      airplane toggle, and widen the converge wait. then re-run.
- [ ] optional UX: surface "N changes still syncing" on the listing (R13 today
      only covers the open detail page).

## phase 15 - android as the default e2e target (next big task)

pivot the compliance matrix's default e2e target to android and make it as pure a
true end-to-end test as possible: drive the app through fundamental OS/user
primitives with as little awareness of the app internals as possible, so a run
exercises exactly what a real device does. android's emulator/vm makes this the
most practical target (linux/web should follow the same principle where they can;
web stays hook-driven because its canvas has no dom).

- [x] first android matrix run on this laptop works end to end: APK build (~70s),
      alice+bob boot, install, appium, and the flows run - `created_lists`,
      `add_and_cycle_item_state`, and the collab `edits_converge_both_ways` all
      pass over the live dht. measured RAM: ~3.6-3.7 GB rss per emulator, ~7.3 GB
      for the pair, with 16+ GB free under load (60 GB total) - ample headroom.
- [x] OS-level primitives implemented on android (no in-app backdoor): go_offline
      /go_online via adb `cmd connectivity airplane-mode`, set_foreground via adb
      `input keyevent KEYCODE_HOME` / `am start`. the backgrounded offline flow
      passes with these.
- [x] make android the default `make test-e2e` (`matrix_run.sh android`); linux
      and web stay as lighter columns via `make test-compliance PLATFORMS=...`.
      docs updated (Makefile, CONTRIBUTING).
- [ ] carry the "no in-app backdoor" principle further and stabilize the offline
      listing flow (see phase 14).
- [ ] keep the driver requestData control channel (VeilidService.setOnline /
      foreground toggle) for linux + web only, until they gain OS-level
      equivalents (linux: real window backgrounding + a network namespace cut).
- [ ] the offline-sync flows (phase 14) then run on android over real OS network
      loss, closing the gap that on android the detach/attach toggle is stubbed.

## phase 16 - failure-injecting veilid-fake for deterministic tests

the public dht drops a watch update to an online viewer only stochastically
(~10-25%) and self-heals an offline node on reconnect (change-inspection), so
some failure modes cannot be reproduced on demand. rather than stand up a real
private veilid cluster, grow the in-process fake (`test/fakes/fake_backend.dart`)
into a controllable veilid-fake that injects failures deterministically. the
real-veilid compliance matrix still runs for real-network confidence; the fake is
for pinning specific failure modes.

- [x] dropped notifications: `FakeDht.dropNextChanges(n)` writes without emitting
      the change event, simulating watch updates the network loses. used by the
      deterministic reconcile test (phase 17).
- [ ] latency/jitter: delay reads/writes/change delivery by a configurable amount.
- [ ] partitions: isolate one actor's network view from the shared dht for a
      window, then heal.
- [ ] reordering/duplication of change events.
- [ ] optionally drive a fake-backed app build through the compliance matrix (a
      dart-define swaps `VeilidListNetwork` for the fake) so ui-level flows can hit
      injected failures too, not just the dart unit layer.

## phase 17 - live view reconcile (done)

- [x] BUG (root cause): `OpenList` stopped re-reading once `_liveSynced`, relying
      solely on the watch; the watch can silently drop an update (a coalesced
      value change, or a peer's post-offline flush the online viewer misses
      ~10-25% of the time), stranding the view an edit behind forever. veilid
      self-heals a node that itself went offline (change-inspection on reconnect),
      but not an online viewer that dropped a notification. fixed: `_tick` keeps a
      slow background reconcile after live-sync (`_kReconcileEveryTicks`), and
      `_resyncIfReconnected` re-reads on every not-ready->ready edge, not only
      before the first live sync.
- [x] deterministic test (`open_list_sync_test.dart`, veilid-fake +
      `fake_async`): drop a peer's watch update, advance virtual time, assert the
      reconcile recovers it. fails 100% on the pre-fix `_tick`, passes with the
      fix. all 41 dart unit/widget tests + analyze green. the real-veilid e2e
      flows (kept) give high-probability real-network coverage on top.

## phase 18 - link-open loading screen

- [x] opening a list from a share link showed the listing (often the empty
      state) for the whole node-startup + join window before the detail page
      pushed, which read as the app ignoring the link. show a loading screen
      instead: `main` resolves the launch link up front and, while the node
      attaches and the join runs, covers the app (`MaterialApp.builder`) with a
      spinner, then pushes the detail page with a zero-duration transition and
      drops the cover - so a launch goes loading -> list, never flashing the
      listing. a normal launch still shows the listing immediately while the
      node connects (local-first), and back from the opened list still lands on
      the listing. (R2) verified: analyze + 41 dart tests green; linux
      compliance 28/29 (the 1 fail, `offline_edits_flush_on_reconnect`, is the
      pre-existing phase-14 flaky offline-proxy flow - reproduced identically on
      an unmodified HEAD tree, so it is not a regression from this change).

## phase 19 - item state ux and qr scanning

- [x] checkbox tap toggles open <-> complete (the common case), press-and-hold
      (or right-click on desktop) opens a state picker for the rest; `blocked`
      joins the shipped set (R7). `ItemState.cycleNext` is gone: a tap is
      `toggled` and the picker offers `ItemState.selectable`. compliance flows
      `add_and_toggle_item_state` and `pick_item_state` cover both paths, and
      `member_state_change_converges` now exercises tap AND picker across
      devices. the widget frontends drive the hold via a new `long_press`
      (a zero-delta scroll, which is what appium's longTap is).
- [x] scan a share link's qr code with the camera to join a list (R1, R2). one
      new plugin (mobile_scanner; camera+barcode have no stdlib route), pinned to
      the browser's own BarcodeDetector on web so nothing loads from a cdn. the
      affordance is hidden where there is no camera (desktop), so the linux
      column skips `scan_link_opens_camera` rather than failing. note: browsers
      only hand out a camera on a secure origin, so the production http web
      deployment (veilid.tech/list) cannot scan until it is served over https -
      android is the working target, mobile web follows the origin.
- [x] app icon redrawn in the arcticons manner: ONE uniform hairline stroke for
      the whole glyph (was 20 for the shield and 17 for the checklist, now 8
      everywhere - ~2.9% of the glyph's width, matching arcticons' default
      stroke of 1 on their 48 canvas), and the contrast dropped from #ffffff on
      #121318 to #e3e2e6 on #1b1b1f so it sits beside a themed icon pack instead
      of shouting over it. the monochrome layer stays white for the system to
      tint. `scripts/build_icons.sh` renders every android/ios/web png from the
      two svgs instead of hand-exporting them (it flattens the ios set, which
      must carry no alpha channel).
- verified: 45 dart tests + analyze green; the changed flows pass on all three
      columns - linux 5/5, android 4/4 (including `pick_item_state` via a real
      appium long-press and two-emulator `member_state_change_converges`), web
      3/3 over veilid-in-wasm. `scan_link_opens_camera` skips on linux (no
      camera) and web (hook-driven, no gesture surface).

## phase 22 - monotonic views and causal ordering

- [x] BUG ("the list bounces between states"): `OpenList` REPLACED a member's
      whole doc on every read and watch event, so an older copy from a lagging
      dht replica regressed that member's contribution and the fold stepped
      backwards - then the next read moved it forward again. the crdt was never
      wrong; the newer copy was thrown away before the fold could compare
      timestamps. fix: merge an incoming member doc into what we hold (per-field
      greatest ts, the same rule `foldList` uses across members), so a view can
      only ever move forward. covered by "a stale read of a member must not move
      the view backwards", which fails on the pre-fix code.
- [x] wall-clock LWW makes conflict resolution depend on the devices' clocks
      agreeing: an edit made after seeing a peer's change loses if the peer's
      clock runs ahead. replace `LogicalTs` with a hybrid logical clock -
      (physical, counter, member), advanced past every timestamp the device
      observes - so a causally-later edit always wins whatever the skew. the
      wire format appends the counter (`[micros, member, counter]`), which an
      older client parses as today's `[micros, member]` and ignores. truly
      concurrent edits (neither side saw the other) still need an arbitrary
      tiebreak; hlc makes it deterministic rather than clock-dependent. covered
      by HybridClock unit tests and an end-to-end flow where a device an hour
      behind still wins after reading its peer; disabling clock observation
      makes that test fail, so it has teeth.

## phase 23 - one write at a time

- [x] BUG (both `offline_edits_flush_*` flows, and silently in ordinary use):
      edits made in quick succession could vanish for every peer while this
      device showed them and the chip read "synced". each edit writes the WHOLE
      member doc, and nothing serialized those writes, so three taps produced
      three overlapping `setDHTValue` calls on one subkey. veilid stamps a write
      with the sequence number of the value the writer held when the write
      STARTED, so all three went out at seq=1; the dht keeps the first value it
      receives at a sequence and discards the rest, however much newer. the
      node's own log shows it: three docs (len=475/684/689) written in the same
      second, the fanout settling on len=475, no offline write queued for the
      others, no error and no retry. fix: `_flush` runs one write at a time and
      coalesces - the doc is a full snapshot, so an edit made while a write is
      in flight just re-sends the latest doc once that write lands.
- [x] BUG: the queued write could then be issued after the record was closed
      (leaving the list right after an edit), which veilid rejects outright,
      losing the edit again. `dispose` defers `closeRecord` until the write loop
      drains. this is what still failed the backgrounded flow after the first
      fix: while foreground sync is on it holds another ref, so only the
      backgrounded variant actually closed the record.
- [x] covered by "edits made in quick succession all reach the dht" (a fake dht
      that models veilid's sequence numbers), "an edit made during a write goes
      out before the record closes", and the `rapid_edits_all_reach_peer` e2e
      flow - which uses no offline hook at all, since being offline was never
      the cause.
- [x] e2e harness: per-app logs (`VEILIST_E2E_LOGDIR`), `VEILIST_DART_DEFINES`
      so `VEILIST_VERBOSE=true` reaches the driver builds, and timestamped
      control-channel transitions. without the node's own log this bug was
      invisible - the app reported success at every step.
- [ ] residual: the write loop is per `OpenList`, so two instances writing the
      same subkey can still collide - editing an item, going back, and renaming
      from the listing at once (`ListRepository.renameList` opens its own
      `OpenList`) is the reachable case. serializing per (record, subkey) in
      `VeilidListNetwork` would close it at the one choke point every writer
      passes through.

## phase 24 - node recovery after an os-level network drop (android)

after phase 23 the two `offline_edits_flush_*` flows pass on linux but still
fail on android, now with NOTHING reaching the peer rather than everything but
the last edit. that change is expected and not a regression: linux fakes the
outage with an in-app detach that takes ~5s, so writes used to escape live
before it took effect (the colliding writes each got a chance), while android
cuts the network at the os level at once, so every edit is now genuinely
queued. measured with per-device logcat and veilid's debug log:

- the edits are NOT lost. the flush attempted while offline reports
  `written_subkeys: ` (empty), so the subkey stays queued, and the previous
  flow's queued writes later flushed for real (`written_subkeys: 0..=0`) about
  five minutes after they were made.
- what fails is the node. after airplane mode is switched off, f's node flaps
  online/offline several times and settles at `outbound=NeedsBootstrap
  inbound=NeedsDialInfoConfirmed`, never printing `PublicInternet ready` again
  for the rest of the flow. raising the budget to 300s (VEILIST_CONVERGE_S)
  does not help; the writes only flushed once the app restarted and the node
  attached cleanly.
- unlike the linux column, nothing tells veilid the network came back: the
  harness toggles airplane mode, so there is no detach/attach. a phone that
  loses signal and regains it is the same case (R12/R13), so this is a product
  question, not only a test one - the app likely has to notice connectivity
  returning and prod the node rather than wait for it to bootstrap itself.

- [x] measured with `node_recovers_after_network_drop`, which times how long the
      node takes to become usable again (the sync chip leaving "offline"):

      | tree                                   | recovery |
      |----------------------------------------|----------|
      | linux, in-app detach/attach            | 8s       |
      | android, os radio cut, no recovery     | never within 180s |
      | android, detach/attach watchdog        | never - the detach does not return |
      | android, `network restart` watchdog    | 42s      |

- [x] a detach/attach is the WRONG remedy: the watchdog fired four times (39s,
      79s, 109s, 150s unusable) and not one produced an `Attaching...` line,
      because `Veilid.instance.detach()` never returns while the network is in
      this state. it would also tear down every open record.
- [x] veilid's own `debug("network restart")` is the right one:
      `network_manager().restart_network()` rebuilds interfaces and sockets with
      the node still attached, so open records survive. `VeilidService` now runs
      a watchdog: unusable for `_kStuckAfter` while we mean to be online ->
      restart the network, retry no more than every `_kRecoveryRetry`, each
      attempt bounded by a timeout so a call that never returns cannot wedge it.
      gated on `_wantOnline`, so the e2e harness's deliberate detach (and any
      future "work offline") is never undone. the log shows the whole chain:
      `Network restarted` -> `PublicInternet ready in 977ms` -> the queued
      offline subkey write flushing one second later.
- [ ] every recovery attempt is logged; if this ever fires in normal use on a
      healthy network, the threshold is too aggressive and wants raising.

with the watchdog, android now passes `offline_edits_flush_on_reconnect` and
`rapid_edits_all_reach_peer`. `offline_edits_flush_while_backgrounded` still
fails, and it is the one case none of this reaches:

- the item added while offline arrives, the state change made just after it does
  not. the node recovers (`Network restarted` -> `ready in 1.99s`) and then the
  offline flush retries every ~5s for the rest of the flow, each attempt ending
  `FanoutResult { kind: Exhausted, consensus_nodes: [], value_nodes: [] }` with
  every SetValueQ and GetValueQ timing out. the node believes it is ready and
  can reach nobody.
- the difference from the flow that now passes is that the app is BACKGROUNDED
  (HOME) for the whole reconnect. android restricts a backgrounded process's
  network and cpu, and veilist runs no foreground service, so there is nothing
  entitled to do this work.
- phase 14 recorded this flow passing on android, which it did - by accident.
  before phase 23 the racing writes escaped live during the ~20s the radio took
  to actually go down, so nothing had to flush from the background at all. now
  the flow tests what its name claims, and the answer is that we cannot do it.

- [x] decided: a backgrounded app syncs when it is next opened. no foreground
      service (a permanent notification for a to-do list is a lot to ask) and no
      WorkManager job. R12 now says this outright, and the flow says what it
      tests: `offline_edits_flush_while_backgrounded` becomes
      `offline_edits_flush_when_reopened` - background, reconnect, come back to
      the app, and every queued edit must reach the peer. what is NOT allowed is
      losing an edit, and that is what the flow guards.
- [ ] check the chip does not claim "synced" while writes are still queued in
      the background - `hasPendingWrites` should keep it on "syncing" (R13), but
      it is only ever read with a list open, so nothing tests it from the
      listing.

confirmed on android with the watchdog and the reworked flow:

| flow                              | result |
|-----------------------------------|--------|
| `node_recovers_after_network_drop`| PASS - usable again in 55s (42s in an earlier run; never, before) |
| `offline_edits_flush_on_reconnect`| PASS |
| `offline_edits_flush_when_reopened`| PASS |
| `rapid_edits_all_reach_peer`      | PASS |

linux stays 17/17, including the three flows that detach the node deliberately
(`offline_edit_reaches_peer_after_reconnect`,
`live_view_reconciles_missed_edits`,
`peer_offline_misses_edit_then_reconnects`) - they are what proves the
`_wantOnline` gate keeps the watchdog from re-attaching underneath a deliberate
detach.

## phase 25 - a member never publishes less than it published (R16)

reported from real use: a mobile client made a batch of edits while the owner
(linux) was offline for days. both came back, sat there without ever
synchronizing, and then the list emptied completely on both devices. the chain,
confirmed by three tests written against it before any fix:

- **the network forgot the record.** storage nodes hold other people's records
  under an lru capped at `remote_max_records` (128 a node off-web,
  `veilid_config.rs`), and nothing in veilist ever re-wrote a record, so a list
  nobody touched for days was evicted from every node holding it. the same
  eviction logs as "RecordIndex(remote): Consistency failure, not enough room
  made for new record" - veilid's own `make_room_for_record` only counts bytes,
  never the record-count limit, so a normal lru eviction takes a should-not-
  happen branch. cosmetic there, the trigger here.
- **an empty network answer counted as a complete read.** `readDocs` chose which
  subkeys to read from the network inspect and set `complete = fromNetwork`, so
  all-null network seqs meant zero subkeys read and a read reported as the whole
  picture. same for a partial answer: a member's subkey the network had lost was
  skipped without clearing `complete`.
- **so both devices declared themselves synced** having read nothing at all -
  the "waited for them to synchronize but they never did" part, with the chip
  saying they already had.
- **the next edit wiped the slot.** every write carries a FULL snapshot of
  `_mine`, and `_mine` was `putIfAbsent(memberIndex, MemberDoc.new)` - a fresh
  empty doc when the slot never loaded. an absent assertion is not a tombstone
  (`foldList` drops any item with no `present`), so everything that device ever
  contributed ceased to exist for every member. nothing could restore it:
  `refresh` deliberately never merged our own slot back, we are its only writer,
  and `localDoc` was nulled at publish, so the record store held the only copy.
- **why both devices, and why "after some time".** `_receive` merges rather than
  replaces, so the peer's open view kept showing the items for the rest of that
  session and the wipe was invisible; the empty doc landed in its local store at
  a higher seq, so the items were gone on its next start.

two separate gaps let the write happen: a joined list became editable the moment
a read was "complete", which the empty read made true with nothing loaded, and
an owner needed even less - `canEdit` was unconditionally true for `isOwner`, so
an open that merely failed to read was enough.

- [x] `readDocs` reads the union of the local and network subkey views, so a
      record the network has forgotten still reads back from this node, and
      reports `complete` only when the network answered AND knew about
      everything this node does. an answer of nothing is never complete.
- [x] `OpenList` tracks `_mineResolved` - we hold the doc already published in
      our slot, or a whole read says the slot is empty - and refuses to write
      before that. `canEdit` requires it, owner included. a read that returned
      no docs at all is never whole: publishing always writes slot 0, so a
      published record always holds at least one doc.
- [x] this device's own doc is persisted per list (`LocalList.localDoc`, no
      longer nulled at publish) and seeded into `_docs` at open, so the record
      store is not the only copy of it and an unreachable network cannot make
      the next edit a wipe. it is written before the network write, so an edit
      that never goes out still survives on the device.
- [x] foreground sync re-writes this device's own doc every
      `kRepublishInterval` (6h) so the record is not evicted while a list sits
      idle. skipped while the list is open, so it never races that list's own
      writes into a sequence collision (phase 23).
- [x] covered by "an edit must not publish a doc that erases this member's own
      items", "a read that found nothing must not report the list as synced",
      "an owner whose doc failed to load must not overwrite it", "this device's
      own doc survives a network that forgot the record", and "foreground sync
      republishes a record nothing has written to". all three of the first ones
      failed before the fix, the first and third by publishing `['bread']` over
      a list that had milk and eggs in it.
- [x] `edits_survive_the_owner_returning_cold` guards the reachable half in the
      compliance matrix: a member edits while the owner is away, the owner
      cold-starts and edits, and nothing may vanish on either device.
- [ ] not covered end to end: a record aging out of the dht cannot be provoked
      from the harness (it needs the storage nodes to evict, which takes days
      and other people's traffic), and the republish interval is 6h with no
      test-only override. the e2e column tests the cold-restart half only.
- [ ] recovery for lists already emptied: nothing here restores data that was
      wiped before this shipped. a device that still holds the old doc could
      republish it, but there is no ui for "put my copy back" and no way to tell
      a wipe from a deliberate clear-out after the fact.

## phase 26 - the roster catches up fast, and says what changed (R17)

two halves of the same complaint: edit a list on one device, pick up another,
and the roster should be current and should say which lists moved.

- [x] foreground sync opens its watches concurrently. `_syncAll` awaited one
      list at a time, so with a roster of n published lists the last one's watch
      was n sequential network round trips away - and every resume from
      background rebuilds all of them, because backgrounding closes them. a
      bounded worker pool (`kForegroundSyncConcurrency`) collapses that to
      roughly one round trip without flooding the node with opens.
- [x] one sync per record at a time. `VeilidListNetwork` refcounts opens, so two
      concurrent `_syncDirty` calls for one record open it twice and the single
      close on background leaves a ref behind - a watch that outlives the
      foreground and a record that never closes. serially this needed a watch
      event to land mid-pass; concurrently it is routine.
- [x] but such an event is remembered, not dropped. dropping it was the first
      cut, on the reasoning that the roster would differ from what the user last
      saw either way - which was wrong: the in-flight read may have started
      before that write landed, and a watch fires once per change, so nothing
      else was coming. `listing_flags_a_peer_edit` failed 3 of 4 real linux runs
      on it (the reads are seconds long, so a peer's write lands mid-sync more
      often than not). the sync now re-runs when the one in flight finishes,
      the same shape as `_flush`'s write loop.
- [x] unseen-change indicator (R17): a list whose content changed since this
      device last looked at it is marked in the listing with a dot and a bold
      title. the listing showed only a title, so a peer's edits were invisible
      until you opened the list and compared from memory.
- [x] `foldDigest`: a stable fnv-1a digest over the folded items (each item's
      id, text and state, in order). persisted, so it cannot use the vm's string
      hashing, which is not promised to be stable across runs. comparing digests
      rather than timestamps means "changed back to what you saw" reads as seen,
      and needs no reasoning about clock skew.
- [x] the title is deliberately NOT in the digest: the listing already renders
      it, so a rename shows there without a mark - and counting it made your own
      rename from the listing come straight back at you as somebody else's
      change (`renaming your own list does not mark it updated` fails with the
      title mixed in).
- [x] only a `complete` read notes content. a partial or empty read folds to
      less than is there, and taking that as the content would mark a list
      changed on the strength of a read that reached nothing (the R16 lesson).
- [x] `LocalList.contentDigest` (what the repository last read) vs `seenDigest`
      (what the user last had on screen); `hasUpdates` is the two disagreeing.
      the detail page marks both on every fold, so looking at a list clears it
      even as a peer keeps editing - but not while it is still fetching, when
      there is nothing on screen to have seen.
- [x] BUG found on the way (proven by `renaming your own list does not mark it
      updated`, which threw "A OpenList was used after being disposed"):
      `_updateSync` checked `_disposed` once BEFORE its awaits and notified
      after them, and `refresh` never checked at all. renaming from the listing
      disposes moments after `open()` kicks off its refresh, so this fired on an
      ordinary path in every debug build. every notify goes through `_notify`
      now, which re-checks at the notify itself.
- [x] covered by dart tests for the digest, the unread transitions, the restart,
      the rename, and `foreground sync opens the roster at once, each record
      once` - which fails both ways: serial sync makes it see 1 record in flight
      instead of 3, and dropping the in-flight guard makes it open one record
      twice.
- [x] `listing_flags_a_peer_edit` in the compliance matrix: b joins, goes back
      to the listing, f edits, and the mark must appear and then clear once b
      looks. the widget frontends (linux, android) query it by finding the dot
      inside the list's tile; web has no route stack to leave, so its hook keeps
      every touched list open and it reports skip. measured on linux: 1 of 4
      runs passed while a mid-sync change was dropped, 3 of 3 once it is
      remembered. the mark landed ~12s after the peer's edit.

## phase 27 - a shared list stays editable offline (R12 regression from R16)

reported from real use: "can't seem to reorder or change the status of items in
a list while the status of that list is offline... at least for lists that are
shared with me".

phase 25 made `canEdit` require `_mineResolved` - this device knowing what its
own member slot already holds - because every write publishes a FULL snapshot of
that slot and writing one built from nothing erases it for everyone. correct
about the write, wrong about the edit:

- [x] a member who has only ever READ a list someone shared with them holds no
      `localDoc`, and nothing is published at their slot. offline, none of the
      four things that resolve a slot can happen (a complete read needs the
      network), so the whole list went read-only. the owner never saw it - their
      `localDoc` is written at create - and it self-heals after one online edit,
      which is why it only showed up on shared lists.
- [x] the edit no longer waits on the slot; the PUBLISH does. an edit lands at
      once - folded, on screen, saved to `localDoc` - and `_flush` sets
      `_publishPending` instead of writing. `_resolveMine` releases it when a
      read accounts for the slot, and that read has merged whatever was already
      there into our doc first, so what goes out is a superset either way.
- [x] the alternative - treating a slot this device has never written as empty
      and publishing at once - was rejected: a non-creator who re-shares hands
      out their OWN slot (DESIGN.md limitations), so a second device on that
      slot would publish over the first's items before ever reading them. the
      merge test below fails that way round.
- [x] the sync chip is unchanged. this only happens while the node is down, when
      it already reads offline, and R13 already covers "saved offline".
- [x] proven first: `a shared list is editable offline before this device has
      edited it` (canEdit false) and `an offline edit on a never-edited shared
      list is kept on-device` (the edit was not even persisted) both failed on
      the phase 25 code. `an edit held back offline publishes a merge, not a
      snapshot` covers the other half, and fails - along with phase 25's `an
      owner whose doc failed to load must not overwrite it` - if the held-back
      write is allowed to go out unmerged.
- [x] `joiner_edits_offline_before_ever_editing` in the compliance matrix: b
      joins, leaves the list, goes offline, REOPENS it offline (an open-time
      read is local-only, so this is the state the report describes), toggles a
      state and reorders, and both must reach f once b is back. run against the
      phase 25 gate it fails on "timed out waiting for state 'complete'" - the
      reported symptom exactly - and passes with the write deferred instead.

## phase 28 - the item you just added is on screen

adding an item appends it to the end of the list, so on a list taller than the
screen the row lands below the fold: the add field clears and nothing visibly
happens. every add past the first screenful looked like it had been swallowed.

- [x] the detail page owns the list's ScrollController and, after the frame that
      lays the new row out, animates to the end. waiting for the frame is what
      makes it land on the new row - `maxScrollExtent` only accounts for it once
      it has been laid out.
- [x] proven first: `adding an item scrolls the list down to show it` adds
      enough items to overflow the viewport and fails without the scroll (the
      newest row is never built, so no finder reaches it).
- [x] `added_item_stays_on_screen` in the compliance matrix: the widget
      frontends' `add_item` already waits for the new text, and a lazy list only
      builds what is near the viewport, so the flow fails on the add itself -
      measured on the linux column, where it times out in waitFor without the
      scroll and passes with it. web drives the model through the hook rather
      than the ui, so it has no viewport to fall out of and skips.
- [x] aiming once is not enough with a keyboard on screen: tapping the add
      button takes focus off the field and it is handed straight back, so the
      keyboard slides out and in AFTER the scroll has been aimed. every frame of
      that resizes the viewport and moves the end of the list down, leaving the
      new row a keyboard's height below the fold. the page re-aims on
      `didChangeMetrics` for `kAddFollowWindow` after an add, so the view
      follows the end while it is still moving and stops before it can fight
      the user.
- [x] proven first: `a new item stays in view when the keyboard resizes the
      list` fakes the view insets. the steady-state case (keyboard already up)
      passed all along; shrinking the viewport one frame after the add is what
      fails. the driver suites cannot cover this - flutter driver's text entry
      bypasses the IME, so no soft keyboard ever appears in them.

## known-flaky linux collaboration flows

measured after the phase 22 work, 15 collab flows on the linux column: 12 pass.
the three failures were attributed by re-running them against 729b63d (the
commit before the conflict-resolution change) in a separate worktree:

- both `offline_edits_flush_*` flows failed on BOTH trees and on BOTH platforms.
  this section first recorded them as an artifact of the linux detach/attach
  proxy, which was wrong: they were the real write collision fixed in phase 23,
  and they pass on linux now. the proxy did make it easy to hit, since the flows
  edit during the ~5s the node takes to detach, so the writes still fan out.
- `rename_reaches_listing` is flaky at roughly 1 run in 3 on BOTH trees
  (current PASS/FAIL/PASS, baseline PASS/FAIL/PASS). it waits for a title to
  reach a peer's LISTING through foreground sync rather than an open list, which
  is the slowest propagation path we have. worth hardening the flow (or the
  path) rather than leaving it as noise that trains people to ignore red. worth
  re-measuring first: it renames moments after an add, so phase 23 may have
  fixed it too. re-measured after phase 25: FAIL in the full column, then PASS
  on three consecutive re-runs of the flow alone - 1 in 4, so phase 23 did not
  fix it and it is still the same flake rather than a regression. re-measured
  again after phase 26: FAIL in the full column, then PASS/PASS/PASS/FAIL on
  four re-runs - still 1 in 4. phase 26 fixed a dropped watch event on this very
  path (it was making the new `listing_flags_a_peer_edit` fail 3 runs in 4), so
  that was a plausible cause and is now ruled out: whatever is left is something
  else.

## phase 21 - honest sync state on join

- [x] the state picker was hard to hit: only the 27dp glyph box carried the
      long-press, well under the 48dp minimum touch target, so a hold usually
      landed on the row and did nothing. the whole row now opens the picker, and
      the checkbox's own hit area is padded out to 48dp with the glyph unchanged.
      covered by a widget test that holds the row's text.

- [x] BUG: after joining (e.g. by scanning a qr code) the list appeared and the
      chip read "synced", then the list kept rewriting itself for a while - it
      looked like history replaying. it was not: the crdt keeps each member's
      latest values, and what was arriving was one MEMBER'S DOC at a time.
      `OpenList.refresh()` set `_liveSynced` after any read that completed while
      the node was ready, and `readDocs` could not say the read was partial
      (`_populatedSubkeys` silently falls back to the local view when the network
      inspect returns TryAgain, and each subkey read swallows its own TryAgain).
      fixed: `readDocs` returns `(docs, complete)`; only a complete read counts
      as a live sync, and a first-ever join holds its spinner until then, so a
      scanned link never lands on a half-built list. covered by
      `open_list_sync_test.dart` ("a partial first read must not be reported as
      fully synced"), which fails on the pre-fix code.

## phase 20 - distribution (signing, izzyondroid, f-droid)

see [DISTRIBUTION.md](DISTRIBUTION.md).

- [x] persistent release signing: `android/app/build.gradle.kts` takes the key
      from `android/key.properties` (local) or `VEILIST_KEYSTORE*` env vars (ci),
      falling back to debug only when nothing is configured;
      `scripts/make_release_key.sh` creates the key once; the release workflow
      decodes it from a secret, refuses to publish a debug-signed apk, and wipes
      it afterwards. the pre-0.3 releases were each signed by a throwaway ci
      debug key (v0.1.0 b86a3c0e..., v0.2.0 32bc2cd8...), so they can never be
      updated in place - 0.3.0 is a clean break, and the last one.
- [x] the version lives only in `pubspec.yaml` (0.3.0+3000, above the legacy run
      numbers); ci no longer injects `--build-name`/`--build-number` and instead
      checks the tag against the pubspec, so a rebuild of a tag is identical.
- [x] the qr scanner decodes in pure dart (`qr_code_dart_scan` over the flutter
      camera plugin) instead of google ml kit: mobile_scanner put
      `libbarhopper_v3.so` + tflite models - proprietary blobs - in the apk,
      which both stores refuse. also drops ~14 MB from the fat apk. web scans a
      captured still (the browser cannot stream frames to dart), native scans
      live.
- [x] the camera plugin's RECORD_AUDIO / storage permissions are stripped in the
      app manifest, and the camera is marked not required so a camera-less device
      can still install.
- [x] AGP's `dependenciesInfo` blob disabled (a google-signed section no
      rebuilder can reproduce), fastlane metadata tree added.
- [ ] screenshots for the store listing (fastlane phoneScreenshots/); izzyondroid
      requires them.
- [ ] apk size vs izzyondroid's ~30 MB guidance. measured on the arm64 split:
      v0.2.0 31.8 MB -> 34.4 MB now. dropping ml kit saved ~5 MB but the pure-dart
      decoder and the camera plugin added more to `libapp.so` (5.5 -> 7.3 MB), and
      `libveilid_flutter.so` (11.8 MB) plus `libflutter.so` (11.6 MB) dominate
      regardless. levers, cheapest first: `--split-debug-info` (strips debug
      symbols out of libapp.so; not obfuscation, so f-droid stays happy), then
      trimming what the veilid core compiles in.
- [ ] izzyondroid submission: app-request issue on their codeberg repodata.
- verified: the signing path was exercised end to end with a throwaway keystore
      (env vars -> gradle -> apksigner reports that cert, not the debug one); the
      published manifest carries only CAMERA + the network permissions, with the
      camera not required; the apk contains no ml kit blob and no AGP
      dependencies blob; apk/web/linux builds, 45 dart tests and the android
      flows `scan_link_opens_camera`, `add_and_toggle_item_state` and
      `pick_item_state` all pass on the new decoder.
- [ ] f-droid reproducible build: build one tag twice from different paths and
      diff the apks; expect rust's embedded build paths to need
      `--remap-path-prefix`. then an fdroiddata recipe with `Binaries:` +
      `AllowedAPKSigningKeys:`.

## dependency maintenance

- [x] android toolchain moved to AGP 8.9.1 + gradle 8.11.1 (was 8.7.3 + 8.9):
      mobile_scanner's camerax 1.6.x refuses to build below AGP 8.9.1. gradle
      stays on 8.x because rust-android-gradle 0.9.6 (veilid's plugin) uses an
      api gradle 9 removed. apk builds green with the veilid rust core.
- [ ] flutter 3.44 warns that support for AGP < 8.11.1 / gradle < 8.14 "will
      soon be dropped". both are still 8.x, so the rust plugin should survive
      the move; do it as its own change, with an apk build to confirm.
- [ ] BUG (release signing): `android/app/build.gradle.kts` still signs release
      builds with the debug config, and the ci runner has no debug keystore, so
      AGP generates a throwaway one per run. proven: v0.1.0 is signed with
      b86a3c0e..., v0.2.0 with 32bc2cd8... - different keys, so android refuses
      to upgrade one release to the next, and a user must uninstall (losing their
      veilid identity, the roster, and every list's writer keypair) to move
      versions. fix: a real release keystore, held as a github actions secret and
      wired through `android/key.properties`, falling back to the debug key for
      local builds. the key must then outlive every release.

- [x] bump app_links to 7.x (only direct dep with a newer resolvable version;
      the other stragglers are transitive and pinned by the flutter 3.44.6 sdk).
      7.x breaking changes are ios-only (ios 13 min + uiscenedelegate migration);
      our targets are linux/android/web and we only use AppLinks()/getInitialLink()
      /uriLinkStream, all stable across 7.x. re-run the link flows to confirm R2.
- [ ] wire scripts/patch_veilid_linux.sh into `make deps` and the ci linux job.
      veilid's linux plugin cmake assumes an in-monorepo build (`git rev-parse`),
      which breaks external pub/git consumption and crashes ci cmake on a "dubious
      ownership" git refusal. the patch was applied by hand to the pub cache, so
      ci and fresh checkouts still failed. the hardened script removes the git
      block entirely (idempotent, fails loud on layout drift). upstream has no
      supported route (same code on veilid main); revisit if that changes.
- [x] ci linux release moved from musl/alpine to glibc/ubuntu. flutter ships only
      a glibc linux engine, so the musl build hit one incompatibility after another
      once the rust.cmake patch let it get further - rust drops the cdylib under
      musl's default crt-static, and the glibc engine needs a libdl.so.2 that musl
      folds into libc. with no musl engine to switch to, glibc is the supported
      route; the switch drops the musl target, gcompat, and the busybox-tar workarounds.

## later

- [ ] remaining item states beyond new/active/complete (obsolete, undecided,
      blocked, deferred) surfaced in the ui (R7 model already supports them)
- [ ] settings screen with "export all" (writes a ../xite/-compatible set of
      markdown files, one per list) and a matching import; both live behind the
      settings screen
- [ ] participant count (R15): the share affordance shows how many members a
      shared list has and reflects shared vs private (never-shared) state
- [ ] member revocation ui (R4): tapping the share affordance opens a dialog to
      "unshare" / "detach" future edits by rotating to new keys (the SMPL schema
      is immutable, so this means reassigning member slots or migrating to a
      fresh record, then re-sharing). needs a design pass.
- [ ] ios/desktop packaging and app-link/universal-link registration

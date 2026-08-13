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
- [x] harness: `VeilidService.setOnline` (detach/attach) exposed via the web hook
      and a flutter-driver requestData handler (test/driver/app.dart) for
      linux/web; android uses OS-level adb (airplane-mode, HOME) instead - no
      in-app backdoor. flows `offline_edits_flush_on_reconnect` (listing) and
      `..._while_backgrounded`.
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

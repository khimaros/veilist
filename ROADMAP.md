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

## dependency maintenance

- [x] bump app_links to 7.x (only direct dep with a newer resolvable version;
      the other stragglers are transitive and pinned by the flutter 3.44.6 sdk).
      7.x breaking changes are ios-only (ios 13 min + uiscenedelegate migration);
      our targets are linux/android/web and we only use AppLinks()/getInitialLink()
      /uriLinkStream, all stable across 7.x. re-run the link flows to confirm R2.

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

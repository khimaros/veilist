# contributing

## toolchain

everything is pinned in `mise.toml` (flutter, rust). install once:

```
mise install
```

the veilid dependency is a git dependency pinned to a released tag in
`pubspec.yaml`. the veilid flutter plugin compiles its own rust native library
during the flutter build (rust-android-gradle on android, cmake on linux), so a
rust toolchain is required even for native builds. the web build needs the
veilid wasm blob; `make wasm` builds it.

## common commands

```
make            # build (alias for make build); default target is web
make run        # run the app locally
make analyze    # static analysis
make fmt        # format dart sources
make test       # dart unit + widget tests
make test-e2e   # python end-to-end tests
make precommit  # format check + analyze + unit tests; run before committing
make wasm       # build the veilid wasm blob into web/wasm/
make install-linux  # register the built linux bundle with the desktop
make clean
```

the app icon is rendered from `assets/icon/*.svg` by `scripts/build_icons.sh`
(needs inkscape); edit the svg and re-run it rather than touching the pngs. that
includes the linux hicolor theme under `linux/packaging/icons`, which cmake
installs into the bundle next to the desktop entry it generates from the
application id - see DESIGN.md for why the entry is what gives the app its name
and icon on a linux desktop.

## workflow

- before starting a task, add it to [ROADMAP.md](ROADMAP.md). mark it done when
  complete.
- keep [DESIGN.md](DESIGN.md) current after architectural changes and
  [README.md](README.md) current after user-visible changes.
- never regress a requirement in [REQUIREMENTS.md](REQUIREMENTS.md).
- run `make precommit` before committing. do not commit; version control is the
  maintainer's job.

## tests

three layers, fastest first:

- **dart unit + widget tests** (`test/`, run with `make test`): the pure
  model/crdt fold, share-link parsing, and the ui pages driven against an
  in-memory fake network. one test plays alice and bob over a shared fake dht
  to prove convergence deterministically.
- **true-ui e2e** (`test/e2e/appium/`, python + `uv` + appium flutter-driver, run
  with `make test-ui-e2e`): drives the real widgets on an android emulator with
  no fakes and no test hook, so it exercises every local-first flow the way a
  person does - create, open (without an endless spinner), add, set state,
  edit, reorder, swipe-delete, the share dialog (qr + both links), open-link
  validation, and delete from the listing. the driven build uses
  `test/driver/app.dart`; see the two-device section below for setup.
- **android e2e** (the default `make test-e2e`, the compliance matrix's android
  column): drives the real app on two emulators (alice + bob) via appium
  flutter-driver - real taps, text, drag-reorder, swipe-delete - plus OS-level
  control via adb (airplane-mode for network loss, HOME for backgrounding) with no
  in-app test backdoor. it runs the shared compliance flows including live
  two-device convergence over the real dht. the most faithful true e2e; needs the
  emulator toolchain once (`make android-e2e-setup`). the pair of emulators is
  ~7 GB rss.
- **linux e2e** (the matrix's linux column, `make test-compliance PLATFORMS=linux`):
  the same flows through the profile desktop app over the dart vm service, real
  widgets and gestures, headless under xvfb. fast (no emulator), but its network/
  backgrounding controls use an in-app detach/attach hook rather than a real OS
  network cut, so it is a rough proxy for the offline flows.
- **web e2e** (the matrix's web frontend, `make test-compliance PLATFORMS=web`):
  builds the web app with the `window.veilistTest` hook
  (`--dart-define=VEILIST_E2E=true`), serves it, and drives the system chrome,
  confirming a real veilid node attaches to the public dht inside the browser (R3,
  R8). flutter web renders to a canvas with no dom to click, so this frontend
  calls the hook rather than the ui - it exercises the network and model but not
  real gestures, and its hook awaits each write, so it cannot reproduce
  concurrent-edit races. needs the veilid wasm blob (`make wasm`, which requires
  the rust toolchain and downloads a matching `wasm-bindgen-cli` on first run).

- **linux desktop integration** (`test/e2e/desktop/`, `make test-linux-desktop`):
  launches the real bundle on a private headless display and reads the window
  back with xprop the way a shell does - its icon and the class it matches to a
  desktop entry - then installs into a throwaway prefix. the only layer that
  looks at the window itself; every other one drives the widgets inside it.

unlike the hermetic dart suite, the collaboration flows in every e2e layer need
the public dht to converge.

### android emulator ui e2e (appium)

the true-ui suite drives the real app on android emulators via appium
flutter-driver. one-time setup installs the emulator and a system image into the
mise android sdk and creates the alice/bob avds:

```
make android-e2e-setup     # test/scripts/android_e2e_setup.sh (downloads a lot)
make test-ui-e2e           # single emulator: test_single_device.py
make test-ui-e2e-two       # two emulators: adds live collaboration (R1,R2,R4)
make test-android-guards   # the identity guards, against a real emulator
```

THIS MACHINE RUNS SEVERAL PROJECTS AGAINST SHARED ADB SERVERS, so the suites
reserve `emulator-5554`/`emulator-5556` BY NAME and another project's emulator
can already be sitting there. `wait-for-device` and `sys.boot_completed` both
pass against a foreign emulator -- a readiness check cannot tell the device you
asked for from any device at all -- so without a guard a run installs onto a
stranger, tests it, reports green, and kills it in the exit trap.

`android_env.sh` therefore asserts identity by AVD NAME, twice, with DELIBERATELY
OPPOSITE policies on an unanswered console:

- `assert_avd_free` before booting: no answer means FREE, because a squatter that
  will not identify itself still holds the port, so our own boot fails loudly.
- `assert_avd_is` after `wait-for-device`: no answer means REFUSE, because by
  then our emulator is certainly answering. an unanswered identity is not a
  matching one. the serial is only recorded for teardown once this passes.

do not "fix" that inconsistency -- it is the point. `make test-android-guards`
exercises every branch against a live emulator, including a foreign AVD holding
the port, and asserts on the refusal MESSAGE rather than the exit code, since
both refusal paths exit 1.

both wrap `test/scripts/appium_e2e_run.sh`, which installs the appium flutter +
uiautomator2 drivers under `test/e2e/appium/.appium` on first run, builds the
`test/driver/app.dart` apk, boots the emulator(s), starts an appium server, and
runs pytest. the two-device run boots two headless emulators (kvm-accelerated):
alice creates and shares a list, bob opens the deep link, and edits converge
both ways over the live dht, so each hop crosses a device boundary.
the android native veilid library is compiled during the build; that needs the
android rust targets (`rustup target add aarch64-linux-android
x86_64-linux-android ...`) and `ANDROID_HOME` set (veilid-core's build.rs reads
it). the toolchain is pinned to AGP 8.7 + gradle 8.9 because veilid's android
plugin (rust-android-gradle 0.9.6) predates gradle 9.

the run builds each role with `--dart-define=VEILIST_IPV4_ONLY=true`. without
it, veilid misreads the emulator's slirp site-local ipv6 (`fec0::`) as a global
address, keeps trying the bootstrap's unreachable ipv6 dial info, and never
attaches. restricting veilid to ipv4 (via `network.addressTypes` in
`VeilidService.startup`) makes it attach in seconds. this is an emulator quirk,
so the flag is off in normal builds and real devices keep dual-stack.
`--dart-define=VEILIST_VERBOSE=true` streams veilid's own logs for diagnosing
attach issues.

### release smoke test

`make test-release-smoke` (needs a booted emulator) builds a real release apk,
launches it, and fails if veilid cannot start. the appium suite only drives
debug/profile builds - the flutter driver extension does not exist in release -
so release-only failures (e.g. the keystore-backed protected store failing to
initialize) are invisible to it. this catches that class of bug.

### cross-platform compliance suite

`make test-compliance` runs the compliance matrix (`test/e2e/matrix/`,
`test/scripts/matrix_run.sh`): one set of flows (`flows.py`) written against a
`Frontend` action abstraction, run against linux, android, and web by a single
driver that prints a frontend x flow matrix. because every frontend runs the
same flow code, the platforms cannot drift - this catches ui regressions like a
share dialog that renders only on some targets, and it found the refresh-clobber
and foreground-sync concurrent-modification bugs.

`PLATFORMS` selects frontends (default all three); e.g.
`make test-compliance PLATFORMS=linux` for a quick local run. linux drives the
app over its dart vm service on a private headless display (needs xvfb), android
reuses the appium emulator/driver infrastructure, and web drives the served
build through the `window.veilistTest` hook (flutter web renders to a canvas, so
there is no view tree to locate). a flow a frontend cannot perform (a ui-only
gesture on web) reports skip, not fail.

## releases

bump `version:` in `pubspec.yaml`, add a changelog entry under
`fastlane/metadata/android/en-US/changelogs/<versionCode>.txt`, then push a
`vX.Y.Z` tag. `.github/workflows/release.yml` builds the android arm64 apk
(signed with the project's release key, from repository secrets) and the linux
x86_64 binary, and attaches both to a github release.

the workflow injects no version of its own - it only checks that the tag matches
the pubspec - so a rebuild of a tag from clean source produces the same artifact.
see [DISTRIBUTION.md](DISTRIBUTION.md) for the signing key, why it must never
change, and what izzyondroid and f-droid need.

the linux tarball is the flutter bundle as-is, so it carries the desktop entry,
the icon theme, and the `install.sh` that registers them with the shell.

note: the linux job builds on ubuntu (glibc) to match flutter's prebuilt linux
engine, which is glibc-linked; the binary needs a comparable glibc at runtime. it
also runs `scripts/patch_veilid_linux.sh` after `pub get`, since veilid's linux
plugin cmake assumes an in-monorepo build (see DESIGN.md "native builds").

## style

- ascii only. lowercase prose in docs, comments, and user-facing strings; caps
  for acronyms or emphasis.
- comments explain why, not what. keep functions small and pure where possible.
- define reusable constants at the top of their source file or a shared file.

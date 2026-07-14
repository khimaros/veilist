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
make clean
```

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
  person does - create, open (without an endless spinner), add, cycle state,
  edit, reorder, swipe-delete, the share dialog (qr + both links), open-link
  validation, and delete from the listing. the driven build uses
  `test/driver/app.dart`; see the two-device section below for setup.
- **browser e2e** (the compliance matrix's web frontend, run with
  `make test-e2e`): builds the web app with the `window.veilistTest` hook
  (`--dart-define=VEILIST_E2E=true`), serves it, and drives the system chrome. it
  confirms a real veilid node starts and attaches to the public dht inside the
  browser (R3, R8) and runs the shared compliance flows - including live
  alice/bob convergence across two browser contexts over the real network.
  `make test-e2e` is exactly the web column of the matrix, so
  `make test-compliance PLATFORMS=web` runs the same thing. unlike the hermetic
  dart suite, the collaboration flows need the public dht to converge.

`make test-e2e` needs the veilid wasm blob; it builds it (`make wasm`) if
missing, then the web app. `make wasm` requires the rust toolchain (mise
provides it) and downloads a matching `wasm-bindgen-cli` on first run.

### android emulator ui e2e (appium)

the true-ui suite drives the real app on android emulators via appium
flutter-driver. one-time setup installs the emulator and a system image into the
mise android sdk and creates the alice/bob avds:

```
make android-e2e-setup     # test/scripts/android_e2e_setup.sh (downloads a lot)
make test-ui-e2e           # single emulator: test_single_device.py
make test-ui-e2e-two       # two emulators: adds live collaboration (R1,R2,R4)
```

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

pushing a `vX.Y.Z` tag runs `.github/workflows/release.yml`, which builds the
android arm64 apk and the linux x86_64 binary (build name taken from the tag)
and attaches both to a github release. the version in `pubspec.yaml` is the
fallback build name.

note: the linux job builds on alpine (musl) with `gcompat`, because flutter's
prebuilt linux engine is glibc-linked - so the binary runs on musl systems via
gcompat rather than being a pure static musl build.

## style

- ascii only. lowercase prose in docs, comments, and user-facing strings; caps
  for acronyms or emphasis.
- comments explain why, not what. keep functions small and pure where possible.
- define reusable constants at the top of their source file or a shared file.

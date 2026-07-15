# veilist build entrypoints. toolchains come from mise (see mise.toml), so we
# invoke flutter/dart through `mise exec` for deterministic builds.

FLUTTER := mise exec -- flutter
DART := mise exec -- dart

# default build target. web is the most portable and is also the browser
# fallback; other targets have platform-native rust build prerequisites.
BUILD_TARGET ?= web

.DEFAULT_GOAL := build

.PHONY: build build-apk build-linux build-web run analyze fmt fmt-check test \
	test-e2e precommit wasm deps clean android-e2e-setup test-ui-e2e \
	test-ui-e2e-two test-release-smoke test-compliance

build: deps
	$(FLUTTER) build $(BUILD_TARGET)

build-apk: deps
	$(FLUTTER) build apk

build-linux: deps
	$(FLUTTER) build linux

# production web build for deployment at veilid.tech/list. builds the wasm blob
# if missing and pins --base-href so assets resolve under /list/ (a plain
# `flutter build web` defaults to / and breaks the sub-path deploy). serve the
# output at build/web with the COOP/COEP headers (see CONTRIBUTING.md).
WEB_BASE_HREF ?= /list/
build-web: deps
	test -f web/wasm/veilid_flutter.js || $(MAKE) wasm
	$(FLUTTER) build web --base-href $(WEB_BASE_HREF)

run: deps
	$(FLUTTER) run

deps:
	$(FLUTTER) pub get
	# rewrite the veilid linux plugin cmake for external consumption (see
	# scripts/patch_veilid_linux.sh); pub get restores it, so re-run every time.
	bash scripts/patch_veilid_linux.sh

analyze:
	$(FLUTTER) analyze

fmt:
	$(DART) format lib test

fmt-check:
	$(DART) format --output=none --set-exit-if-changed lib test

test:
	$(FLUTTER) test

# browser e2e: the web build boots in the system chrome and the shared
# compliance flows run against a real veilid-in-wasm node. this is the web column
# of the compliance matrix; the full cross-platform sweep is `make test-compliance`.
test-e2e:
	test/scripts/matrix_run.sh web

precommit: fmt-check analyze test

# build the veilid wasm blob and stage it under web/wasm/ for the web build.
wasm:
	scripts/build_wasm.sh

# one-time: install the emulator + a system image into the mise android sdk and
# create the alice/bob avds.
android-e2e-setup:
	test/scripts/android_e2e_setup.sh

# true ui end-to-end suite via appium flutter-driver (python/pytest). single
# drives all local-first ui flows on one emulator; two adds live two-device
# collaboration over the dht. see test/e2e/appium/ and test/scripts/appium_e2e_run.sh.
test-ui-e2e:
	test/scripts/appium_e2e_run.sh single

test-ui-e2e-two:
	test/scripts/appium_e2e_run.sh two

# release smoke test: catches release-only startup failures (e.g. the veilid
# protected store) that the debug-only appium suite cannot see. needs a booted
# emulator; pass its serial as SERIAL (default emulator-5554).
test-release-smoke:
	test/scripts/release_smoke.sh $(SERIAL)

# cross-platform compliance matrix: the same flows run against every frontend
# (linux/android/web) through one Frontend abstraction, so they cannot drift.
# PLATFORMS selects frontends (default all three); e.g. PLATFORMS=linux for a
# quick local run. see test/e2e/matrix/ and test/scripts/matrix_run.sh.
test-compliance:
	test/scripts/matrix_run.sh $(PLATFORMS)

clean:
	$(FLUTTER) clean

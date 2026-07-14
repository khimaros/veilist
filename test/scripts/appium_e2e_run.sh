#!/usr/bin/env bash
# true ui end-to-end suite driven by appium flutter-driver (python/pytest).
# boots the emulator(s), builds the test_driver apk (which enables the flutter
# driver extension), starts an appium server, then runs the python tests. a
# green run proves the real app behaves for a user, not just the repository.
#
# usage: test/scripts/appium_e2e_run.sh [single|two]   (default: single)
#   single - one emulator, test_single_device.py (all local-first ui flows)
#   two    - two emulators, adds test_two_device.py (live collaboration)
#
# prerequisites: test/scripts/android_e2e_setup.sh (emulator + system image +
# avds) and the appium drivers installed under test/e2e/appium/.appium (this
# script does that on first run).
set -euo pipefail

MODE="${1:-single}"
# this script lives at test/scripts/, so the repo root is two levels up.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/test/scripts/android_env.sh"

export APPIUM_HOME="$ROOT/test/e2e/appium/.appium"
APPIUM="$ROOT/test/e2e/appium/node_modules/.bin/appium"
APK="$ROOT/build/app/outputs/flutter-apk/app-debug.apk"
ALICE=emulator-5554
BOB=emulator-5556
APPIUM_PID=""

cleanup() {
  echo "== tearing down =="
  [ -n "$APPIUM_PID" ] && kill "$APPIUM_PID" 2>/dev/null || true
  adb -s "$ALICE" emu kill >/dev/null 2>&1 || true
  [ "$MODE" = two ] && adb -s "$BOB" emu kill >/dev/null 2>&1 || true
}
trap cleanup EXIT

boot() { # $1=avd $2=port $3=serial
  echo "== booting $1 ($3) =="
  emulator -avd "$1" -port "$2" -no-window -no-audio -no-boot-anim \
    -no-snapshot -gpu swiftshader_indirect -accel on \
    >"/tmp/emu_$1.log" 2>&1 &
  adb -s "$3" wait-for-device
  for _ in $(seq 1 150); do
    local bc; bc="$(adb -s "$3" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
    if [ "$bc" = "1" ] && adb -s "$3" shell pm path android >/dev/null 2>&1; then
      sleep 5; return 0
    fi
    sleep 2
  done
  echo "!! $3 did not finish booting" >&2; return 1
}

# install the flutter + uiautomator2 drivers into the project appium home once.
ensure_drivers() {
  if ! $APPIUM driver list --installed 2>&1 | grep -q 'flutter@'; then
    $APPIUM driver install --source=npm appium-flutter-driver@3.9.0
  fi
  if ! $APPIUM driver list --installed 2>&1 | grep -q 'uiautomator2@'; then
    $APPIUM driver install uiautomator2
  fi
}

# the apk must use test/driver/app.dart as its entrypoint so the flutter driver
# extension is registered. ipv4-only keeps veilid off the emulator's misdetected
# slirp ipv6 (see VeilidService.startup).
build_apk() {
  echo "== building driver apk =="
  (cd "$ROOT" && mise exec -- flutter build apk --debug \
    -t test/driver/app.dart --dart-define=VEILIST_IPV4_ONLY=true \
    --target-platform android-x64)
}

adb start-server >/dev/null 2>&1 || true
ensure_drivers
build_apk
boot veilist_alice 5554 "$ALICE"
[ "$MODE" = two ] && boot veilist_bob 5556 "$BOB"

echo "== starting appium =="
env APPIUM_HOME="$APPIUM_HOME" "$APPIUM" --address 127.0.0.1 --port 4723 \
  --base-path / --log-timestamp --log-no-colors >/tmp/appium.log 2>&1 &
APPIUM_PID=$!
for _ in $(seq 1 30); do
  curl -s http://127.0.0.1:4723/status >/dev/null 2>&1 && break; sleep 1
done

echo "== running pytest ($MODE) =="
cd "$ROOT/test/e2e/appium"
export VEILIST_APK="$APK"
if [ "$MODE" = two ]; then
  uv run pytest -v
else
  uv run pytest -v test_smoke.py test_single_device.py
fi

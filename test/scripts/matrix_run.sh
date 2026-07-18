#!/usr/bin/env bash
# runs the compliance matrix (test/e2e/matrix/) against the selected frontends
# and prints a frontend x flow result matrix. sets up each frontend's environment:
#   linux   - builds the profile driver app (dart vm service)
#   android - boots two emulators (a peer for the collab flows), builds the
#             driver debug apk, starts appium
#   web     - builds the e2e web app (window.veilistTest hook) for playwright
#
# usage: test/scripts/matrix_run.sh [linux] [android] [web]  (default: all three)
set -euo pipefail

# this script lives at test/scripts/, so the repo root is two levels up.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

FRONTENDS=("$@")
[ ${#FRONTENDS[@]} -eq 0 ] && FRONTENDS=(linux android web)
want() { printf '%s\n' "${FRONTENDS[@]}" | grep -qx "$1"; }

# boot an emulator (headless, kvm-accelerated) and block until it finishes
# booting. $1=avd $2=port $3=serial
boot_emu() {
  emulator -avd "$1" -port "$2" -no-window -no-audio -no-boot-anim \
    -no-snapshot -gpu swiftshader_indirect -accel on >"/tmp/emu_matrix_$3.log" 2>&1 &
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

FLAGS=()
APPIUM_PID=""
cleanup() {
  [ -n "$APPIUM_PID" ] && kill "$APPIUM_PID" 2>/dev/null || true
  if want android; then
    adb -s emulator-5554 emu kill >/dev/null 2>&1 || true
    adb -s emulator-5556 emu kill >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if want linux; then
  echo "== building linux profile driver =="
  mise exec -- flutter build linux --profile -t test/driver/app.dart
  FLAGS+=(--linux)
fi

if want web; then
  # build the e2e web app to a SEPARATE output dir so it never clobbers the
  # production build/web. the e2e build carries the window.veilistTest backdoor
  # and a "/" base-href (production uses /list/), so deploying it would be broken
  # and insecure - keep the two artifacts apart.
  echo "== building e2e web (window.veilistTest hook) -> build/web-e2e =="
  [ -f web/wasm/veilid_flutter.js ] || scripts/build_wasm.sh
  mise exec -- flutter build web --dart-define=VEILIST_E2E=true --base-href / \
    --output "$ROOT/build/web-e2e"
  FLAGS+=(--web)
fi

if want android; then
  source "$ROOT/test/scripts/android_env.sh"
  export APPIUM_HOME="$ROOT/test/e2e/appium/.appium"
  APPIUM="$ROOT/test/e2e/appium/node_modules/.bin/appium"
  echo "== building driver debug apk =="
  mise exec -- flutter build apk --debug -t test/driver/app.dart \
    --dart-define=VEILIST_IPV4_ONLY=true --target-platform android-x64
  # two emulators so the collaboration flows have a peer to join on; with one,
  # every collab flow skips. mirrors the old two-device ui test.
  echo "== booting emulators (alice 5554, bob 5556) =="
  boot_emu veilist_alice 5554 emulator-5554
  boot_emu veilist_bob 5556 emulator-5556
  echo "== installing apk on both (appium sessions stay noReset) =="
  APK="$ROOT/build/app/outputs/flutter-apk/app-debug.apk"
  for s in emulator-5554 emulator-5556; do
    adb -s "$s" install -r "$APK"
    # pre-grant the camera so the qr-scanner flow never stalls behind the
    # runtime permission dialog (a system window the flutter driver cannot see).
    adb -s "$s" shell pm grant com.khimaros.veilist android.permission.CAMERA || true
  done
  echo "== starting appium =="
  env APPIUM_HOME="$APPIUM_HOME" "$APPIUM" --address 127.0.0.1 --port 4723 \
    --base-path / --log-no-colors >/tmp/appium_matrix.log 2>&1 &
  APPIUM_PID=$!
  for _ in $(seq 1 30); do
    curl -s http://127.0.0.1:4723/status >/dev/null 2>&1 && break
    sleep 1
  done
  export VEILIST_APK="$APK"
  export VEILIST_UDID=emulator-5554
  export VEILIST_UDID_2=emulator-5556
  FLAGS+=(--android)
fi

cd "$ROOT/test/e2e/matrix"
uv sync >/dev/null
# MATRIX_ARGS forwards extra matrix.py flags (e.g. --collab, --flow NAME) so a
# caller can target a subset without re-running the whole matrix.
uv run python matrix.py "${FLAGS[@]}" ${MATRIX_ARGS:-}

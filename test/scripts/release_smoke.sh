#!/usr/bin/env bash
# release smoke test. the appium ui e2e can only drive debug/profile builds
# (the flutter driver extension does not exist in release), so release-only
# startup failures - like the keystore-backed protected store failing to
# initialize - slip past it. this builds a real release apk, launches it on a
# booted emulator, and fails if veilid reports a startup error in the logs.
#
# prerequisites: a booted emulator (test/scripts/android_e2e_setup.sh once, then
# boot one). pass its serial as $1 (default emulator-5554).
set -euo pipefail

# this script lives at test/scripts/, so the repo root is two levels up.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/test/scripts/android_env.sh"

SERIAL="${1:-emulator-5554}"
PKG=com.khimaros.veilist
APK="$ROOT/build/app/outputs/flutter-apk/app-x86_64-release.apk"

echo "== building release apk (x86_64, verbose veilid logs) =="
(cd "$ROOT" && mise exec -- flutter build apk --release --target-platform android-x64 \
  --split-per-abi --dart-define=VEILIST_VERBOSE=true)

echo "== installing on $SERIAL =="
adb -s "$SERIAL" install -r "$APK" >/dev/null
adb -s "$SERIAL" logcat -c
adb -s "$SERIAL" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1

# a release build that starts veilid clears the protected store and moves on to
# attaching. a broken one throws before that. watch the log both ways.
echo "== watching veilid startup (up to 90s) =="
deadline=$((SECONDS + 90))
while [ $SECONDS -lt "$deadline" ]; do
  log="$(adb -s "$SERIAL" logcat -d 2>/dev/null)"
  if grep -qiE 'could not initialize the protected store|VeilidAPIException: Internal|FATAL EXCEPTION' <<<"$log"; then
    echo "!! release build failed to start veilid:" >&2
    grep -iE 'protected store|VeilidAPIException|FATAL' <<<"$log" | tail -6 >&2
    exit 1
  fi
  # verbose veilid logs show network/attach activity once the core is up.
  if grep -qiE 'network_manager|AttachmentState|attaching|rpc_processor|routing_table' <<<"$log"; then
    echo "== release smoke passed: veilid core started, no protected-store error =="
    exit 0
  fi
  sleep 3
done
echo "!! timed out waiting for veilid to start in the release build" >&2
adb -s "$SERIAL" logcat -d 2>/dev/null | grep -iE 'flutter :|veilid|protected' | tail -20 >&2
exit 1

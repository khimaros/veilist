#!/usr/bin/env bash
# one-time setup for the two-device android emulator e2e: installs the emulator
# and a system image into the mise-managed android sdk, then creates two avds
# (alice, bob). idempotent. all tools resolve through mise (see mise.toml).
set -euo pipefail

SYS_IMAGE="system-images;android-35;default;x86_64"
AVDS=(veilist_alice veilist_bob)

ANDROID_HOME="$(mise where android-sdk)"
JAVA_HOME="$(mise where java)"
# pin the avd location: cmdline-tools honor XDG_CONFIG_HOME but the emulator
# binary does not, so without this they disagree on where avds live.
export ANDROID_AVD_HOME="$HOME/.android/avd"
export ANDROID_HOME ANDROID_SDK_ROOT="$ANDROID_HOME" JAVA_HOME
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
mkdir -p "$ANDROID_AVD_HOME"

echo "android sdk: $ANDROID_HOME"
echo "java:        $JAVA_HOME"

# accept licenses, then install emulator + platform + system image. `yes` takes
# SIGPIPE (141) once sdkmanager stops reading, which is expected, so this line
# tolerates a nonzero pipe status; a genuine license problem surfaces as the
# install below failing.
yes | sdkmanager --licenses >/dev/null 2>&1 || true
sdkmanager "emulator" "platform-tools" "platforms;android-35" "$SYS_IMAGE"

for avd in "${AVDS[@]}"; do
  echo "creating avd: $avd"
  echo no | avdmanager create avd -n "$avd" -k "$SYS_IMAGE" -d pixel_6 --force
done

echo "android e2e setup complete: ${AVDS[*]}"

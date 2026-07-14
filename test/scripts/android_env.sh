# sourceable android/emulator env for appium + gradle rust builds.
# keep in sync with test/scripts/android_e2e_setup.sh.
ANDROID_HOME="$(mise where android-sdk)"
JAVA_HOME="$(mise where java)"
export ANDROID_AVD_HOME="$HOME/.android/avd"
export ANDROID_HOME ANDROID_SDK_ROOT="$ANDROID_HOME" JAVA_HOME
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/28.2.13676358"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

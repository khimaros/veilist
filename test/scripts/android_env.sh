# sourceable android/emulator env for appium + gradle rust builds.
# keep in sync with test/scripts/android_e2e_setup.sh.
ANDROID_HOME="$(mise where android-sdk)"
JAVA_HOME="$(mise where java)"
export ANDROID_AVD_HOME="$HOME/.android/avd"
export ANDROID_HOME ANDROID_SDK_ROOT="$ANDROID_HOME" JAVA_HOME
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/28.2.13676358"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

# this machine runs several agents against shared adb servers, so veilist gets
# its own. without this an unpinned `adb` lands on the default 5037 and claims
# every usb device on the box, including phones mid-flash.
#
# set here rather than at each call site because adb clients read this variable
# themselves -- so anything that shells out to adb inherits it, including the
# emulator's own internal adb calls and gradle. NOTE the name: `ADB_SERVER_PORT`
# is SILENTLY IGNORED by adb, only this spelling works.
export ANDROID_ADB_SERVER_PORT="${ANDROID_ADB_SERVER_PORT:-5042}"

# a serial that cannot exist: veilist drives emulators, which are adopted over
# localhost 5555-5585 regardless, so restricting usb costs nothing and stops us
# ever claiming a phone that belongs to another project.
ADB_SENTINEL="VEILIST_EMULATORS_ONLY"

# start veilist's own restricted adb server, or refuse if this port already
# holds an unrestricted one.
#
# TWO SEPARATE HAZARDS, both silent. a bare `adb` finding NO server on this port
# AUTO-STARTS AN UNRESTRICTED one, which then claims every usb device on the box
# -- including a phone mid-flash in another project. and `start-server` against
# an EXISTING server is a no-op that reports success, so having run it is NOT
# evidence the server is restricted. the restriction is visible only in the
# cmdline, so that is where to look.
ensure_adb_server() {
  adb --one-device "$ADB_SENTINEL" start-server >/dev/null 2>&1 || true
  local n
  n="$(ps -eo args 2>/dev/null \
       | grep -c "^adb -L tcp:${ANDROID_ADB_SERVER_PORT} .*--one-device ${ADB_SENTINEL}" || true)"
  if [ "${n:-0}" -lt 1 ]; then
    echo "!! adb server on ${ANDROID_ADB_SERVER_PORT} is not restricted to ${ADB_SENTINEL}:" >&2
    ps -eo args 2>/dev/null | grep "^adb -L tcp:${ANDROID_ADB_SERVER_PORT} " >&2 || true
    echo "!! refusing: it can claim usb devices belonging to other projects." >&2
    return 1
  fi
}

# an emulator started without -port takes the LOWEST FREE console port, so
# another project's emulator can already be sitting on the one we reserve by
# name. adb names devices by port, so `wait-for-device` and `sys.boot_completed`
# both PASS against a foreign emulator -- a readiness check cannot tell the
# device it asked for from any device at all. we would then install onto it,
# test it, report green, and kill it in the exit trap.
#
# identity is the avd name, never the serial. returns non-zero if a DIFFERENT
# avd already holds this serial. usage: assert_avd_free <serial> <wanted-avd>
#
# NO ANSWER MEANS FREE HERE, AND ONLY HERE: we are about to boot on this port,
# and a squatter that will not name itself still holds the port, so our emulator
# fails to bind and we find out. that reasoning does NOT carry to the moment we
# start DRIVING a serial -- see assert_avd_is.
assert_avd_free() {
  local existing
  existing="$(avd_on_serial "$1")"
  if [ -n "$existing" ] && [ "$existing" != "$2" ]; then
    echo "!! $1 is already running avd '$existing', expected '$2'" >&2
    echo "!! refusing to touch it. stop that emulator or boot ours elsewhere." >&2
    return 1
  fi
}

# confirm the emulator now ANSWERING on a serial is the one we just booted.
# usage: assert_avd_is <serial> <wanted-avd>
#
# assert_avd_free passes on a console that will not answer. if a foreign
# emulator holds the port, ours fails to bind while `wait-for-device` succeeds
# against THEIRS -- so everything downstream runs on a stranger's device and the
# exit trap kills it. re-assert after the boot, when our own emulator is
# certainly answering.
#
# AN UNANSWERED IDENTITY IS NOT A MATCHING ONE: empty REFUSES here, because
# "could not find out" and "it is ours" are different answers.
assert_avd_is() {
  local existing
  existing="$(avd_on_serial "$1")"
  if [ "$existing" != "$2" ]; then
    echo "!! $1 answers as avd '${existing:-<no answer>}', expected '$2'" >&2
    echo "!! refusing: our emulator did not get this port." >&2
    return 1
  fi
}

# the avd name the emulator console reports for a serial, empty if it will not
# say. this reaches the console on the EVEN port rather than adb on the odd one,
# so it answers while the transport is still `offline` -- identity is knowable
# ~24s before `sys.boot_completed` is. assert identity first, wait for readiness
# second; it is the only ordering that works during a race.
avd_on_serial() {
  local out
  # `emu avd name` answers "<name>\nOK", so keep only the first line.
  out="$(adb -s "$1" emu avd name 2>/dev/null | tr -d '\r')"
  echo "${out%%$'\n'*}"
}

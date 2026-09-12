#!/usr/bin/env bash
# exercises the emulator identity guards in android_env.sh against a REAL
# emulator. these guards are what stop a run from installing onto, testing, and
# then killing another project's emulator that happens to hold the port we
# reserve by name -- so a guard nobody has watched refuse is not a guard.
#
# boots veilist_alice on 5570 (not 5554/5556) so it cannot collide with a real
# suite run, and kills only what it booted. takes about 30 seconds.
#
# usage: test/scripts/android_env_test.sh
#
# NOT part of `make precommit`: it boots an emulator, which is too heavy for a
# pre-commit gate. run it when touching the guards.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/test/scripts/android_env.sh"
ensure_adb_server || exit 1

AVD=veilist_alice
PORT=5570
SERIAL=emulator-$PORT
FOREIGN=hmux_audio     # a real avd from another project on this box

pass=0; fail=0

# BOTH refusal paths exit 1, so an exit code cannot say WHICH one ran. assert on
# the discriminating message too: when two branches share a return value, the
# message is the only thing identifying the branch.
# usage: check <label> <ok|refuse> <expected-substring|-> <cmd...>
check() {
  local label="$1" want="$2" want_msg="$3"; shift 3
  local out rc got
  out="$("$@" 2>&1)"; rc=$?
  got=ok; [ $rc -ne 0 ] && got=refuse
  if [ "$got" != "$want" ]; then
    echo "FAIL  $label -> $got, wanted $want"; fail=$((fail+1))
  elif [ "$want_msg" != "-" ] && ! printf '%s' "$out" | grep -qF -- "$want_msg"; then
    echo "FAIL  $label -> $got (right code, WRONG BRANCH): no '$want_msg'"; fail=$((fail+1))
  else
    echo "PASS  $label -> $got"; pass=$((pass+1))
  fi
  [ -n "$out" ] && echo "      $out"
}

echo "== nothing on the port: the console will not answer =="
# the two helpers take OPPOSITE policies on an unanswered identity, on purpose.
check "assert_avd_is   refuses empty" refuse "'<no answer>'" \
      assert_avd_is "$SERIAL" "$AVD"
check "assert_avd_free allows empty"  ok     - \
      assert_avd_free "$SERIAL" "$AVD"

echo
echo "== booting $AVD on $PORT =="
emulator -avd "$AVD" -port "$PORT" -no-window -no-audio -no-boot-anim \
  -no-snapshot -gpu swiftshader_indirect -accel on >"/tmp/emu_${AVD}_test.log" 2>&1 &
EMU_PID=$!
cleanup() {
  echo
  echo "== cleanup =="
  adb -s "$SERIAL" emu kill >/dev/null 2>&1 || true
  sleep 3
  kill "$EMU_PID" 2>/dev/null || true
  # verify by comm: a `pgrep -f` pattern matches this script's OWN command line
  # and would report the emulator alive forever.
  ps -eo comm | grep -qx 'qemu-system-x86_64-headless' \
    && echo "WARN: an emulator is still running" || echo "clean: no emulator"
}
trap cleanup EXIT

# identity is answerable from the console long before the device is usable, so
# this waits on the console rather than on sys.boot_completed.
for i in $(seq 1 90); do
  [ -n "$(avd_on_serial "$SERIAL")" ] && { echo "console answered after ~$((i*2))s"; break; }
  sleep 2
done

echo
echo "== our own avd holds the port =="
check "assert_avd_is   accepts ours"  ok - assert_avd_is "$SERIAL" "$AVD"

echo
echo "== a DIFFERENT project's avd holds the port =="
# the message must name the FOREIGN avd, not '<no answer>'. this is the fact the
# whole design rests on: the console will identify another project's emulator.
check "assert_avd_is   refuses theirs" refuse "answers as avd '$AVD'" \
      assert_avd_is "$SERIAL" "$FOREIGN"
check "assert_avd_free refuses theirs" refuse "already running avd '$AVD'" \
      assert_avd_free "$SERIAL" "$FOREIGN"

echo
echo "== meta: prove the message assertion can actually FAIL =="
# right exit code, impossible message. subshell so the counters are untouched.
# without this, every PASS above could be an exit-code check in disguise.
meta="$(check "deliberate wrong branch" refuse "THIS STRING CANNOT APPEAR" \
        assert_avd_is "$SERIAL" "$FOREIGN" 2>&1)"
if printf '%s' "$meta" | grep -qF 'WRONG BRANCH'; then
  echo "PASS  harness rejects a right-code/wrong-branch result"; pass=$((pass+1))
else
  echo "FAIL  harness accepted a wrong branch -- the message assertion is inert"
  fail=$((fail+1))
fi
echo "      $meta"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]

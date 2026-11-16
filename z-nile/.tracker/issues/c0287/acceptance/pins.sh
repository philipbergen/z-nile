#!/usr/bin/env bash
# c0287 AC1: the fakes' shape and the census of waits, as text pins (run by check.sh only, never promoted: the gate
# must not freeze fakecli's text). Run from the z-nile home.
set -u
FAKE=tests/lib/fakecli.luau
C=tests/acceptance/c0117
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
fail=0
# the line of one fake mode (from its `name) ` to the first `;;`, joined), as c0279's pins.sh reads it
mode() { awk -v m="$1) " 'index($0, m) && !f {f=1} f {printf "%s ", $0} f && /;;/ {exit}' "$FAKE"; }

# the four entries this chore changes, whole: the orphan's pid file, hour-long grandchild and hold; the late push held
# on <fakes>/late-go and made only when it came; the authors' keepalive until the review's CLI has started, with the
# FAKE_START_DELAY knob that spawns nothing when unset
for m in orphan late waitreview waitplain; do
  want=$(grep -F -e "$m: " "$here/fakecli-modes.expected" | head -n 1 | sed "s/^$m: //")
  if [[ -z $want || "$(mode "$m")" != "$want" ]]; then
    echo "DIFFERS ($m fake): not the reviewed text (acceptance/fakecli-modes.expected)"; fail=1
  fi
done
# every CLI fake marks that its step's CLI has started, with a builtin redirection (nothing spawned), after the step is
# read and before the mode runs
marker="'[ -z \"\$step\" ] || : > \"\$FAKE_DIR/started.\$step\"',"
n=$(grep -cxF -e "		$marker" "$FAKE")
[[ $n -eq 1 ]] || { echo "MISSING (every CLI fake): the started marker line, exactly once ($n found)"; fail=1; }
at=$(grep -nxF -e "		$marker" "$FAKE" | head -n 1 | cut -d: -f1)
stepAt=$(grep -n "'step=\$(printf" "$FAKE" | head -n 1 | cut -d: -f1)
caseAt=$(grep -nF -e "'case \"\$mode\" in'," "$FAKE" | head -n 1 | cut -d: -f1)
if [[ -z $at || -z $stepAt || -z $caseAt ]] || (( at < stepAt || at > caseAt )); then
  echo "MISPLACED (every CLI fake): the started marker is not between the step= line and the mode's case"; fail=1
fi
# c0279's pins on the same fake (its first line and its stop, cap, push and tool entries) still hold
if [[ -f tests/acceptance/c0279/pins.sh ]]; then
  bash tests/acceptance/c0279/pins.sh || { echo "FAILS: c0279's pins (tests/acceptance/c0279/pins.sh)"; fail=1; }
else
  echo "MISSING: tests/acceptance/c0279/pins.sh"; fail=1
fi
# the census: in c0117's specs outside dispatch-cli (c0279's file), the only waits are control-cli's `within` and
# trackerstate's wall-clock loop; no file-absence wait anywhere
for f in "$C"/*.spec.luau; do
  [[ $f == */dispatch-cli.spec.luau ]] && continue
  case $f in
    */control-cli.spec.luau | */trackerstate.spec.luau) want=1 ;;
    *) want=0 ;;
  esac
  # any wait call, however the scheduler is reached (`task.wait(`, `require("@lune/task").wait(`, `t:wait(`)
  n=$(grep -cE '[.:]wait\(' "$f")
  [[ $n -eq $want ]] || { echo "CENSUS ($f): $n wait calls, expected $want"; fail=1; }
  if grep -qF -e "absentAfter" "$f"; then echo "PRESENT ($f): absentAfter"; fail=1; fi
done
exit $fail

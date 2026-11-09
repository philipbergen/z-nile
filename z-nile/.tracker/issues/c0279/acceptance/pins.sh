#!/usr/bin/env bash
# c0279 AC1: the shape of the fix, as text pins on the promoted spec and the fake (run by check.sh only, never promoted:
# the gate must not freeze fakecli's text). Run from the z-nile home.
set -u
SPEC=tests/acceptance/c0117/dispatch-cli.spec.luau
FAKE=tests/lib/fakecli.luau
fail=0
need() { # need <label> <file> <fixed string>
  if ! grep -qF -e "$3" "$2"; then echo "MISSING ($1): $3"; fail=1; fi
}
absent() { # absent <label> <file> <fixed string>
  if grep -qF -e "$3" "$2"; then echo "PRESENT ($1): $3"; fail=1; fi
}
# the line of one fake mode
# (from its `name) ` to the first `;;`, joined)
mode() { awk -v m="$1) " 'index($0, m) && !f {f=1} f {printf "%s ", $0} f && /;;/ {exit}' "$FAKE"; }

absent "no wall-clock wait on a file the grandchild would touch" "$SPEC" "absentAfter"
need "stop case proves the kill by the pid" "$SPEC" 'deadWithin(grandchildPid("grandchild-stop"), 60)'
need "cap case proves the kill by the pid" "$SPEC" 'deadWithin(grandchildPid("grandchild-cap"), 60)'
need "only 'No such process' is a death" "$SPEC" 'No such process'
need "stall limit only a real stall reaches" "$SPEC" 'stall_seconds = 60'
need "the one issue that tests a stall keeps 2 s" "$SPEC" '[dispatch]\nstall_seconds = 2\ntool_seconds = 30\n'

stop=$(mode stop)
cap=$(mode cap)
push=$(mode push)
for pair in "stop:$stop" "cap:$cap"; do
  name=${pair%%:*}; line=${pair#*:}
  [[ $line == *"grandchild-$name.pid"* ]] || { echo "MISSING ($name fake): the pid file"; fail=1; }
  [[ $line == *"exec sleep 120"* ]] || { echo "MISSING ($name fake): a grandchild that outlives any wait"; fail=1; }
  [[ $line == *"sleep 2; touch"* ]] && { echo "PRESENT ($name fake): the 2 s touch"; fail=1; }
done
[[ $stop == *'FAKE_DELAY'* ]] || { echo "MISSING (stop fake): FAKE_DELAY"; fail=1; }
[[ $stop == *'sleep 120 ;;'* ]] || { echo "MISSING (stop fake): the silent hold after the stop"; fail=1; }
[[ $stop == *'while :; do echo'* ]] && { echo "PRESENT (stop fake): a heartbeat would hide a stop that kills nothing"; fail=1; }
n=$(grep -o 'FAKE_DELAY' <<<"$push" | wc -l)
[[ $n -ge 2 ]] || { echo "MISSING (push fake): FAKE_DELAY before git and before gh"; fail=1; }
exit $fail

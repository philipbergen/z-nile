#!/usr/bin/env bash
# c0287 mutation check: clone the prototype commit (proto-c0287, 0e79784e3) into a fresh `mktemp -d` folder outside
# every checkout, apply one mutant there, write a reduced copy of the spec holding the setup case and the cases its row
# names (subset.py), run it without the step's variables (nostep.sh), log to experiments/mutant-<id>.txt, and remove the
# clone on any exit (a ./zn run limit included). No checkout is ever edited. Each edit refuses a pattern that is not
# unique. Bounded by ./zn run:
#   ./zn run --time 1800 -- bash <this file> <mutant id>
set -u
[[ $# -eq 1 ]] || { echo "usage: mutants.sh <mutant id>" >&2; exit 2; }
id=$1
PROTO=0e79784e3
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
log="$here/mutant-$id.txt"
src=$(git -C "$here" rev-parse --path-format=absolute --git-common-dir) || exit 2
t=$(mktemp -d "${TMPDIR:-/tmp}/c0287-mut.XXXXXX") || exit 2
t=$(cd "$t" && pwd -P)
case $t in */c0287-mut.*) ;; *) echo "mutants.sh: unexpected scratch path $t" >&2; exit 2 ;; esac
trap 'rm -rf "$t"' EXIT
trap 'exit 143' TERM INT HUP
# the scratch folder's parent is no checkout, so nothing below it can reach the real repository's work tree
if git -C "$(dirname "$t")" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "mutants.sh: $t is inside a checkout" >&2; exit 2
fi
wt="$t/r"
git clone -q --shared --no-checkout "$src" "$wt" || exit 2
git -C "$wt" checkout -q "$PROTO" || exit 2
git -C "$wt" remote remove origin
cd "$wt" || exit 2
SPEC=z-nile/tests/acceptance/c0117/control-cli.spec.luau
FAKE=z-nile/tests/lib/fakecli.luau
RUNNER=z-nile/engine/runner.luau
# edit <file> <old> <new>: the old text must occur exactly once
edit() {
  python3 -I -c '
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
n = s.count(old)
if n != 1:
    sys.exit(f"mutants.sh: {n} matches in {p} for {old!r}")
open(p, "w").write(s.replace(old, new))
' "$@" || exit 2
}
envs=() words=() spec=$SPEC
case $id in
  M1) # the root stall limit back to 3 s (no tool limit) on a slow machine
    edit $SPEC $'stall_seconds = 120\ntool_seconds = 240\n' $'stall_seconds = 3\n'
    envs=(FAKE_DELAY=3); words=("trips the wire: exit 5" "late code push" "the publish broker") ;;
  M2) # the supervisor ignores its lifeline's end
    edit $RUNNER '"    if (!$got) { group(15); select(undef, undef, undef, 2); group(9); exit(137); } }",' '"    if (!$got) { $rin = q(); } }",'
    words=("a step dies with its dispatcher") ;;
  M3) # M2, with the orphan fake's hold cut to 20 s: its exit lets the supervisor kill the group
    edit $RUNNER '"    if (!$got) { group(15); select(undef, undef, undef, 2); group(9); exit(137); } }",' '"    if (!$got) { $rin = q(); } }",'
    edit $FAKE 'kill -9 "$ZN_DISPATCHER_PID"; sleep 3600 ;;' 'kill -9 "$ZN_DISPATCHER_PID"; sleep 20 ;;'
    words=("a step dies with its dispatcher") ;;
  M4) # the late push lands during the step (pushed before the step ends)
    edit $FAKE "perl -e 'setpgrp(0,0); exec @ARGV' sh -c 'n=0;" "\"\$ZN_REAL_GIT\" push -q origin HEAD:main; perl -e 'setpgrp(0,0); exec @ARGV' sh -c 'n=0;"
    words=("late code push") ;;
  E5) # not a mutant: how long the dead dispatcher's supervisor still holds the step's run.lock (its TERM, 2 s, KILL)
    edit $SPEC $'\t\t\tt.expect(within(60, free(`{dirOf("c0050")}/run.lock`))).toBe(true)\n' $'\t\t\tlocal t0 = os.clock()\n\t\t\tlocal gone = within(60, free(`{dirOf("c0050")}/run.lock`))\n\t\t\tprint(string.format("E5: run.lock free %.2f s after the dispatcher\'s lock was", os.clock() - t0))\n\t\t\tt.expect(gone).toBe(true)\n'
    words=("a step dies with its dispatcher") ;;
  M6) # the author's keepalive gone (the slow start of the nested ./zn kept)
    edit $FAKE 'tool_use","id":"t1","name":"Bash"}]}}'"'"'; ( n=0; while [ ! -f "$FAKE_DIR/started.zz-review" ] && [ $n -lt 1200 ]; do echo '"'"'{"type":"system"}'"'"'; sleep 0.5; n=$((n+1)); done ) & hb=$!; ' 'tool_use","id":"t1","name":"Bash"}]}}'"'"'; hb=0; '
    edit $FAKE 'waitplain) echo '"'"'{"type":"system"}'"'"'; ( n=0; while [ ! -f "$FAKE_DIR/started.zz-review" ] && [ $n -lt 1200 ]; do echo '"'"'{"type":"system"}'"'"'; sleep 0.5; n=$((n+1)); done ) & hb=$!; ' 'waitplain) echo '"'"'{"type":"system"}'"'"'; hb=0; '
    envs=(FAKE_START_DELAY=12); words=("long nested review" "reviewer silent but within") ;;
  M7) # the author ignores its nested steps' beats
    edit $RUNNER $'\t\t\t\t\t\tif beats[beat] ~= nil then\n\t\t\t\t\t\t\tquiet = 0\n\t\t\t\t\t\tend\n' ''
    words=("long nested review" "reviewer silent but within") ;;
  M8) # M7, with the keepalive covering the whole review (it waits for a marker no fake writes)
    edit $RUNNER $'\t\t\t\t\t\tif beats[beat] ~= nil then\n\t\t\t\t\t\t\tquiet = 0\n\t\t\t\t\t\tend\n' ''
    python3 -I -c '
import sys
p = sys.argv[1]
s = open(p).read()
old = "while [ ! -f \"$FAKE_DIR/started.zz-review\" ]"
if s.count(old) != 2:
    sys.exit("mutants.sh: M8 expects 2 keepalives")
open(p, "w").write(s.replace(old, "while [ ! -f \"$FAKE_DIR/started.never\" ]"))
' $FAKE || exit 2
    words=("long nested review" "reviewer silent but within") ;;
  M9) # the runner ignores the tool limit
    edit $RUNNER 'local limit = if adapters.toolRunning(acc) then r.toolSeconds else r.stallSeconds' 'local limit = r.stallSeconds'
    words=("reviewer silent but within") ;;
  M10) # c0095's closer limits dropped (the root's 120 s apply)
    edit $SPEC $'\t\t\t["pickman/.tracker/issues/c0095/.models.toml"] = "[dispatch]\\ntool_seconds = 10\\nstall_seconds = 10\\n",\n' ''
    words=("long nested review") ;;
  M11) # a broker that never returns
    edit z-nile/engine/broker.luau $'function broker.serve(dir: string, token: string, push: (sha: string) -> (boolean, string))\n\tpcall(function()' $'function broker.serve(dir: string, token: string, push: (sha: string) -> (boolean, string))\n\tif string.find(dir, "/broker$") then\n\t\trequire("@lune/task").wait(90)\n\tend\n\tpcall(function()'
    spec=z-nile/tests/acceptance/c0117/trackerstate.spec.luau; words=("sets up a fixture repository" "two brokers on one folder") ;;
  M12) # a death read from any failure of kill -0 (a permission error, a missing kill)
    edit $SPEC 'return not r.ok and string.find(r.stderr, "No such process", 1, true) ~= nil' 'return not r.ok'
    words=("a step dies with its dispatcher") ;;
  T0) # not a mutant: the setup case and a trivial one, the baseline for T1's timing
    words=("dispatch vet is not a command") ;;
  T1) # not a mutant: the setup case and the concurrent runs, timed (the 600 s bound against the case's own time)
    words=("dispatch vet is not a command" "each run fetches into refs of its own") ;;
  *) echo "mutants.sh: no mutant $id" >&2; exit 2 ;;
esac
sub="${spec%.spec.luau}-mut.spec.luau"
python3 -I "$here/subset.py" "$spec" "$sub" "${words[@]}" || exit 2
bash "$here/nostep.sh" "$wt" "$log" ${envs[@]+"${envs[@]}"} -- "${sub#z-nile/}"
code=$?
{ echo "mutant: $id (a clone of $PROTO under \$TMPDIR)"; git diff --stat; } >> "$log"
echo "$id exit=$code (log $log)"

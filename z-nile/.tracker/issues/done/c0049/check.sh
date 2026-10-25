#!/usr/bin/env bash
# Acceptance checks for c0049. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0049 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0049"

check "AC1: tests/run runs spec files concurrently, aggregates and orders results, keeps its summary" \
  lune run tests/run -- "$A/parallel-runner.spec.luau"

check "AC2: z-nile/lib/par.sh runs stages concurrently with buffered, ordered, timed output (bash 3.2 safe)" \
  lune run tests/run -- "$A/par-stages.spec.luau"

check "AC3: no two spec files share a .cache fixture directory" \
  lune run tests/run -- "$A/spec-isolation.spec.luau"

# AC4 and AC5 inspect real gate runs.
in_order() { # $1: output; $2...: extended regexes that must each match a line, in this order
  local out=$1 last=0 n re
  shift
  for re in "$@"; do
    n=$(grep -nE -- "$re" <<<"$out" | head -1 | cut -d: -f1)
    [[ -n $n ]] || { echo "missing line matching: $re"; return 1; }
    [[ $n -gt $last ]] || { echo "out of order: $re"; return 1; }
    last=$n
  done
}
T='\([0-9]+\.[0-9]s\)' # elapsed seconds in a stage header

gate_prints_timings() {
  local out
  out=$(./check.sh --affected 2>&1) || { echo "$out" | tail -30; return 1; }
  in_order "$out" \
    "^== format \(stylua --check\) $T" \
    "^== lint \(selene\) $T" \
    "^== types \(luau-lsp analyze, src with Roblox definitions\) $T" \
    "^== types \(luau-lsp analyze, tests \+ scripts \+ z-nile with Lune definitions\) $T" \
    "^== build \(rojo\) $T" \
    "^== tests \(affected\)" \
    "^gate wall time: [0-9]+\.[0-9]s$" \
    "^GATE PASSED \(affected\)$" || return 1
  [[ $(tail -n 1 <<<"$out") == "GATE PASSED (affected)" ]] || { echo "GATE PASSED must stay the last line"; return 1; }
}
gate_stages_are_started_together() { # structure: five par_start lines, all before the single par_wait
  local starts waits first_wait last_start
  starts=$(grep -cE '^par_start ' ./check.sh)
  waits=$(grep -cE '^par_wait' ./check.sh)
  [[ $starts -eq 5 && $waits -eq 1 ]] || { echo "expected 5 par_start and 1 par_wait lines, got $starts and $waits"; return 1; }
  first_wait=$(grep -nE '^par_wait' ./check.sh | head -1 | cut -d: -f1)
  last_start=$(grep -nE '^par_start ' ./check.sh | tail -1 | cut -d: -f1)
  [[ $last_start -lt $first_wait ]] || { echo "a par_start comes after par_wait: the stages are not all started together"; return 1; }
}
check "AC4a: check.sh starts the five static stages together, then waits once" gate_stages_are_started_together


gate_static_failure() {
  local d="$PWD/.cache/c0049-gate" out rc
  rm -rf "$d"
  mkdir -p "$d/.cache"
  rsync -a --exclude=.git --exclude=.cache --exclude=.worktree --exclude=sourcemap.json ./ "$d/" || return 1
  [[ -s .cache/globalTypes.d.luau ]] && cp .cache/globalTypes.d.luau "$d/.cache/"
  printf 'local   unformatted   =   1\n' >"$d/tracker/zz-unformatted.luau"
  out=$(cd "$d" && ./check.sh --full 2>&1) && rc=0 || rc=$?
  rm -rf "$d"
  [[ $rc -ne 0 ]] || { echo "the gate passed with an unformatted file"; return 1; }
  in_order "$out" \
    "^== format \(stylua --check\) .*FAILED" \
    "^== lint \(selene\)" \
    "^== types \(luau-lsp analyze, src" \
    "^== types \(luau-lsp analyze, tests" \
    "^== build \(rojo\)" || { echo "$out" | tail -30; return 1; }
  if grep -qE "^== tests|^GATE PASSED" <<<"$out"; then echo "tests ran, or the gate passed, after a failed static stage"; return 1; fi
}

full_suite_in_parallel() { # twice: shared-state flakiness shows up as a failure on one of the runs
  local i
  for i in 1 2; do lune run tests/run -- --jobs 8 || return 1; done
}
check "AC6: the whole suite passes under the parallel runner with 8 jobs, twice in a row" full_suite_in_parallel

skills_carry_the_rule() {
  local testing=skills/zz-test/SKILL.md raft=skills/zz-execute/SKILL.md section
  grep -qE '^## Speed' "$testing" || { echo "testing skill has no '## Speed' section"; return 1; }
  section=$(awk '/^## Speed/{f=1; next} /^## /{f=0} f' "$testing")
  local w
  for w in "concurrently" "monitor" "optimi[sz]e" "slowest" "chore" "par.sh" "PICKMAN_JOBS"; do
    grep -qiE -- "$w" <<<"$section" || { echo "the Speed section does not mention: $w"; return 1; }
  done
  grep -qi "gate wall time" "$raft" || { echo "execute-raft does not tell the executor to record the gate wall time"; return 1; }
}
check "AC7: the testing and execute-raft skills carry the standing speed rule" skills_carry_the_rule

finish

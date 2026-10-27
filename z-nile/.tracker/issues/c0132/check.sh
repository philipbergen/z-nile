#!/usr/bin/env bash
# Acceptance checks for c0132. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0132 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0132"

# The spec's cases share one setup, so it runs once (here, outside `check`: list mode refuses it); a check then
# requires its named cases to exist in the spec and not fail, and the spec to have loaded.
report_out=$(lune run tests/run -- "$A/killed-report.spec.luau" 2>&1)
report() { # $1...: case-name prefixes that must exist in the spec and not fail
  local spec="$A/killed-report.spec.luau" c
  [[ -f $spec ]] || { echo "missing $spec"; return 1; }
  if grep -q "could not load spec" <<<"$report_out"; then echo "$report_out"; return 1; fi
  grep -Eq "^[0-9]+ passed, [0-9]+ failed, 1 spec files$" <<<"$report_out" || { echo "$report_out" | tail -20; return 1; }
  for c in "$@"; do
    tr -d "\n\t" < "$spec" | grep -qF "it(\"$c" || { echo "$spec has no case starting \"$c\""; return 1; }
    if grep -F "FAIL" <<<"$report_out" | grep -qF ":: $c"; then grep -F -A1 ":: $c" <<<"$report_out"; return 1; fi
  done
}

jailed_report() { # report's cases, and on macOS the jailed case must have run, not returned early
  report "$@" || return 1
  if [[ $(uname -s) == Darwin && ! -f .cache/c0132-jailed-ran ]]; then
    echo "the jailed case did not run: run this check outside any other sandbox, so the specs are jailed"
    return 1
  fi
}

check "AC1: a killed sweeper's report names the launcher, the run's top process and whether it lives (a refused probe as alive), and the specs' group" jailed_report \
  "a sweeper killed alone: the report names the launcher, the live top process and the specs' group" \
  "the report says when the run's top process is gone" \
  "when jailed, a top process outside the jail (its probe refused) reads as alive"
check "AC2: the report says whether the watchdog lives, lists every other process still in the group and reads them, before the group is stopped; what it can't read is unread" report \
  "a sweeper killed alone: the watchdog is alive and every process still in the group is listed" \
  "a whole group killed with the watchdog in reach, as from outside the jail: gone, nothing left" \
  "the watchdog killed with the sweeper and the rest left: read as neither group signal" \
  "a group pgrep can't read is unread, never an empty group" \
  "the group is still stopped after the report"
check "AC3: the report says when, how many seconds after the specs started, and the memory the OS saw when the sweeper died" report \
  "the report says when, and how long after the specs started, the sweeper died" \
  "the report gives the memory the OS saw: percent free and swap used, read on macOS"
check "AC4: no report without a sweeper or without a signal death" report \
  "a launcher not running a sweeper reports nothing, and a signal death stays 128+n" \
  "a sweeper that exits, even with a failing status, gets no report"
check "AC5: the runner gives its launcher its own pid as PICKMAN_REAP_TOP, and no spec inherits it" report \
  "the runner gives its launcher its own pid as PICKMAN_REAP_TOP, and no spec inherits it"
check "AC6: the testing skill says how to read the report, and that the next one goes to c0167" report \
  "the testing skill says how to read a killed sweeper's report"

# AC7: real jailed runs, which no spec can make (a jail can't be nested, and a real run's watchdog is outside it). A
# fixture checkout under .cache holds a copy of the runner and one probe spec per run; this check.sh runs outside the
# jail, so each fixture run jails itself, sweeper included. Each run's sweeper dies a different way, and its report
# must read it: the whole group signalled from inside the jail (a spec), the sweeper's pid alone while the specs still
# run (a spec that goes on after it), and the whole group signalled from outside (this check, to the group the probe
# wrote down).
real_readings() {
  [[ $(uname -s) == Darwin ]] || { echo "not macOS: no jail, nothing to check"; return 0; }
  local top fx rel out job g waited
  top=$(git rev-parse --show-toplevel) || return 1
  fx="$PWD/.cache/c0132-real"
  rm -rf "$fx" && mkdir -p "$fx/repo/z-nile/tests/probe" || return 1
  for rel in z-nile/tests/run.luau z-nile/tests/lib z-nile/.luaurc z-nile/lib/ac.sh z-nile/lib/fence.sh z-nile/lib/git-hooks \
    .luaurc rokit.toml .gitignore; do
    [[ -e $top/$rel ]] || continue
    mkdir -p "$fx/repo/$(dirname "$rel")" && cp -R "$top/$rel" "$fx/repo/$rel" || return 1
  done
  probe() { # $1: name, $2: the perl the probe spec runs
    printf '%s\n' '--!strict' 'local process = require("@lune/process")' 'local t = require("@tests/lib/t")' \
      "return t.spec(\"$1\", function(it)" "	it(\"$1\", function()" \
      "		process.exec(\"perl\", { \"-e\", [[$2]], \".cache/group\" })" "		t.expect(1).toBe(1)" "	end)" "end)" \
      > "$fx/repo/z-nile/tests/probe/$1.spec.luau"
  }
  probe inside 'kill "KILL", -getpgrp()'
  probe alone 'select(undef, undef, undef, 0.5); kill "KILL", getpgrp(); select(undef, undef, undef, 3)'
  probe outside 'open my $f, ">", $ARGV[0] or die; print $f getpgrp(); close $f; select(undef, undef, undef, 30)'
  git init -q -b main "$fx/repo" || return 1
  [[ $(git -C "$fx/repo" rev-parse --show-toplevel) == "$(cd "$fx/repo" && pwd -P)" ]] || { echo "not a fixture repository"; return 1; }
  git -C "$fx/repo" add -A && git -C "$fx/repo" -c user.name=dev -c user.email=dev@example.invalid commit -qm runner || return 1
  run() { (cd "$fx/repo/z-nile" && PICKMAN_TEST_FENCE= exec lune run tests/run -- "tests/probe/$1.spec.luau" 2>&1); }
  reads() { # $1: the run, $2: its output, $3: an extended regex its who line must match
    grep -q "the jail's sweeper was killed (signal 9)" <<<"$2" || { echo "$1: no killed sweeper's report (not jailed?):"; tail -5 <<<"$2"; return 1; }
    grep -Eq "^tests/run: who: .*$3" <<<"$2" || { echo "$1: the report does not read it:"; grep "who:" <<<"$2"; return 1; }
  }
  out=$(run inside)
  reads inside "$out" "; watchdog alive \(pid [0-9]+\); 0 other process\(es\) still in the group; reading: the whole group was signalled from inside the jail, or the sweeper alone after the specs ended$" || return 1
  out=$(run alone)
  reads alone "$out" "; watchdog alive \(pid [0-9]+\); [1-9][0-9]* other process\(es\) still in the group; reading: the sweeper's pid alone was signalled$" || return 1
  rm -f "$fx/repo/z-nile/.cache/group"
  run outside > "$fx/outside.out" &
  job=$!
  waited=0
  while [[ ! -s $fx/repo/z-nile/.cache/group && $waited -lt 600 ]]; do perl -e 'select(undef, undef, undef, 0.1)'; waited=$((waited + 1)); done
  g=$(cat "$fx/repo/z-nile/.cache/group" 2>/dev/null)
  [[ $g =~ ^[0-9]+$ ]] || { wait "$job"; cat "$fx/outside.out"; echo "the outside probe wrote no group"; return 1; }
  kill -KILL -- "-$g"
  wait "$job"
  reads outside "$(cat "$fx/outside.out")" "; watchdog gone; 0 other process\(es\) still in the group; reading: the whole group was signalled from outside the jail$" || return 1
  rm -rf "$fx"
}
check "AC7: in real jailed runs, the report reads a group signal from inside the jail, the sweeper's pid alone, and a group signal from outside" real_readings

finish

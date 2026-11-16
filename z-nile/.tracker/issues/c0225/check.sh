#!/usr/bin/env bash
# Acceptance checks for c0225. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0225 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0225"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# The spec's cases share one setup, so it runs once; a check then requires its named cases to exist in the spec and
# not fail, the spec to have loaded, and no case that no criterion names to have failed.
SPEC="$A/sweep-settle.spec.luau"
rm -f .cache/c0225-sweep-settle/jailed-cases-ran # the jailed cases write it afresh: an old marker vouches for nothing
report_out=$(lune run tests/run -- "$SPEC" 2>&1)
# every case some criterion names: the indented case lines of the check calls below
named=$(grep -E '^  "' "$HERE/check.sh" | sed -E 's/^  "//; s/" ?\\?$//')
is_named() { # $1: a case name; true if a criterion names it
  local k
  while IFS= read -r k; do [[ -n $k && $1 == "$k" ]] && return 0; done <<<"$named"
  return 1
}
whole_run() { # the summary's failure count matches the FAIL lines, and a failing case no criterion names fails all
  local line c failed lines
  failed=$(sed -nE 's/^[0-9]+ passed, ([0-9]+) failed, 1 spec files$/\1/p' <<<"$report_out")
  lines=$(grep -cE "^FAIL .* :: " <<<"$report_out")
  [[ $failed == "$lines" ]] || { echo "the run counts ${failed:-no} failure(s) but names $lines:"; tail -20 <<<"$report_out"; return 1; }
  while IFS= read -r line; do
    c=${line#*:: }
    [[ $c == "sets up" ]] && { echo "the spec's set-up failed:"; grep -F -A2 -- "$line" <<<"$report_out"; return 1; }
    is_named "$c" || { echo "a case no criterion names failed:"; grep -F -A2 -- "$line" <<<"$report_out"; return 1; }
  done < <(grep -E "^FAIL .* :: " <<<"$report_out")
}
report() { # $1...: case names that must exist in the spec and not fail; and the spec's whole run (whole_run)
  local c
  [[ -f $SPEC ]] || { echo "missing $SPEC"; return 1; }
  if grep -q "could not load spec" <<<"$report_out"; then echo "$report_out" | tail -20; return 1; fi
  grep -Eq "^[0-9]+ passed, [0-9]+ failed, 1 spec files$" <<<"$report_out" || { echo "$report_out" | tail -20; return 1; }
  whole_run || return 1
  for c in "$@"; do
    tr -d "\n\t" <"$SPEC" | grep -qF "it(\"$c\"" || { echo "$SPEC has no case \"$c\""; return 1; }
    if grep -E "^FAIL" <<<"$report_out" | grep -qF ":: $c"; then grep -F -A2 ":: $c" <<<"$report_out"; return 1; fi
  done
}
jailed_report() { # report's cases, and on macOS the jailed cases must have run, not returned early
  report "$@" || return 1
  if [[ $(uname -s) == Darwin && ! -f .cache/c0225-sweep-settle/jailed-cases-ran ]]; then
    echo "the jailed cases did not run: run this check outside any other sandbox, so the specs are jailed"
    return 1
  fi
}


# AC5 and AC9: one real jailed run of a fixture copy of the runner, made the way c0168's prep made it, whose one spec
# is acceptance/real-run.probe.luau (never a spec of the suite: it burns a core for up to 20 s). This check.sh runs
# outside the jail, so the fixture's run jails itself and its own sweeper runs unseamed, as every real run's does. The
# run happens once per check.sh process ($$ is this script's pid in every subshell) and leaves its verdicts in $rr_out.
rr_out="$(pwd -P)/.cache/c0225-real-$$"
rr_fx="$(pwd -P)/.cache/c0225-real"
rr_cleanup() { # every path out: stop the leftover only if it is still the probe's re-execing perl, drop the fixture
  local pid cmd
  pid=$(cat "$rr_fx/repo/z-nile/.cache/left.pid" 2>/dev/null)
  if [[ $pid =~ ^[0-9]+$ ]]; then
    cmd=$(ps -o command= -p "$pid" 2>/dev/null)
    [[ $cmd == *'@ARGV if time < $ARGV[1]'* ]] && kill -KILL "$pid" 2>/dev/null
  fi
  rm -rf "$rr_fx"
  return 0
}
real_run() {
  [[ -f $rr_out/done ]] && return 0
  rm -rf "$rr_out" && mkdir -p "$rr_out" || return 1
  if [[ $(uname -s) != Darwin ]]; then : >"$rr_out/skip"; : >"$rr_out/done"; return 0; fi
  local top pid fails n
  top=$(git rev-parse --show-toplevel) || return 1
  rm -rf "$rr_fx" && mkdir -p "$rr_fx/repo/z-nile/tests/probe" "$rr_fx/repo/z-nile/lib" || return 1
  # the runner and its guards, every path built from $top
  cp -R "$top/z-nile/tests/run.luau" "$top/z-nile/tests/lib" "$rr_fx/repo/z-nile/tests/" || { rr_cleanup; return 1; }
  cp -R "$top/z-nile/lib/ac.sh" "$top/z-nile/lib/cpu.sh" "$top/z-nile/lib/fence.sh" "$top/z-nile/lib/git-hooks" "$rr_fx/repo/z-nile/lib/" || { rr_cleanup; return 1; }
  cp "$top/z-nile/.luaurc" "$rr_fx/repo/z-nile/" && cp "$top/.luaurc" "$top/rokit.toml" "$top/.gitignore" "$rr_fx/repo/" || { rr_cleanup; return 1; }
  cp "$A/real-run.probe.luau" "$rr_fx/repo/z-nile/tests/probe/real.spec.luau" || { rr_cleanup; return 1; }
  git init -q -b main "$rr_fx/repo" || { rr_cleanup; return 1; }
  [[ $(git -C "$rr_fx/repo" rev-parse --show-toplevel) == "$(cd "$rr_fx/repo" && pwd -P)" ]] || { echo "not a fixture repository"; rr_cleanup; return 1; }
  git -C "$rr_fx/repo" add -A && git -C "$rr_fx/repo" -c user.name=dev -c user.email=dev@example.invalid commit -qm runner || { rr_cleanup; return 1; }
  # a top-level run of the fixture's runner, which jails itself; a CPU cap bounds it apart from the runner it tests.
  # ZN_MEASURED=1: the runner's one-time measurement wrapper (z-nile/lib/bounded.pl) is not part of what is tested
  (cd "$rr_fx/repo/z-nile" && ulimit -t 120 && ZN_MEASURED=1 lune run tests/run -- tests/probe/real.spec.luau) >"$rr_out/out" 2>&1
  echo "$?" >"$rr_out/rc"
  # the leftover is gone only after five failed probes in a row, 50 ms apart (one probe can miss it), within 3 s
  pid=$(cat "$rr_fx/repo/z-nile/.cache/left.pid" 2>/dev/null)
  echo "$pid" >"$rr_out/pid"
  if [[ $pid =~ ^[0-9]+$ ]]; then
    fails=0 n=0
    while [[ $fails -lt 5 && $n -lt 60 ]]; do
      if kill -0 "$pid" 2>/dev/null; then fails=0; else fails=$((fails + 1)); fi
      n=$((n + 1))
      perl -e 'select(undef, undef, undef, 0.05)'
    done
    if [[ $fails -ge 5 ]]; then echo gone >"$rr_out/left"; else echo alive >"$rr_out/left"; fi
  fi
  rr_cleanup
  : >"$rr_out/done"
}
real_case() { # $1: the probe's case name, which must exist and not fail in the real run
  [[ -f $rr_out/skip ]] && return 0
  tr -d "\n\t" <"$A/real-run.probe.luau" | grep -qF "it(\"$1\"" || { echo "the probe has no case \"$1\""; return 1; }
  grep -Eq "^[0-9]+ passed, [0-9]+ failed, 1 spec files$" "$rr_out/out" || { echo "the real run did not finish:"; tail -20 "$rr_out/out"; return 1; }
  if grep -E "^FAIL" "$rr_out/out" | grep -qF ":: $1"; then grep -F -A3 ":: $1" "$rr_out/out"; return 1; fi
}
real_leftover() {
  real_run || return 1
  [[ -f $rr_out/skip ]] && { echo "not macOS: no jail, nothing to check"; return 0; }
  real_case "leaves a detached leftover that re-execs itself in a loop" || return 1
  [[ $(cat "$rr_out/rc") == 0 ]] || { echo "the real run failed ($(cat "$rr_out/rc")):"; tail -20 "$rr_out/out"; return 1; }
  # at least one: another run's dying process can be counted too on a busy machine (c0168 owns that count), seen once in 4
  [[ $(grep -cE '^sweeper: stopped [1-9][0-9]* process\(es\) the specs left running$' "$rr_out/out") == 1 ]] || { echo "the run's sweep did not count its leftover:"; tail -20 "$rr_out/out"; return 1; }
  [[ $(cat "$rr_out/pid") =~ ^[0-9]+$ ]] || { echo "the probe wrote no leftover pid"; return 1; }
  [[ $(cat "$rr_out/left" 2>/dev/null) == gone ]] || { echo "the leftover $(cat "$rr_out/pid") outlived the run"; return 1; }
}
real_cap() {
  real_run || return 1
  [[ -f $rr_out/skip ]] && { echo "not macOS: no jail, nothing to check"; return 0; }
  real_case "a sweep of fifty-one scans, ten of them stopping, ends with the command's status"
}
# AC10: the promoted spec reads the run's lock and tests whether it runs jailed, as c0076's does, and repo-fence's scan
# refuses those two names in any file its ALLOWED table does not list (design review 001 F1). This file must not spell
# them either (the scan reads every check.sh), so it checks for the entry's key; which names the entry gives is the
# scan's own case, run on a promoted copy in Implementation step 4.
allowed() {
  grep -qF '["z-nile/tests/acceptance/c0225/sweep-settle.spec.luau"] = {' tests/tooling/repo-fence.spec.luau ||
    { echo "repo-fence's ALLOWED has no entry for the promoted spec"; return 1; }
}

check "AC1: a leftover the sweep's first four scans miss is still stopped and counted, and the command's status passes through" jailed_report \
  "when jailed, a leftover the first four scans miss is still stopped"
check "AC2: the sweep ends after five empty scans in a row, with the command's status and no count" jailed_report \
  "when jailed, the sweep ends after five empty scans in a row"
check "AC3: a scan that stops something starts the count of empty scans again" jailed_report \
  "when jailed, a scan that stops something starts the count of empty scans again"
check "AC4: the empty scans that end a sweep are at least 50 ms apart, timed between two kills inside the loop" jailed_report \
  "when jailed, the empty scans that end a sweep are at least 50 ms apart"
check "AC5: in a real jailed run of the runner, whose sweep is unseamed, a detached leftover that re-execs itself in a loop is stopped and counted, and the run passes" real_leftover
check "AC6: a seam entry that is neither a pid nor a pid@scan (a leading zero included) is ignored, never a wider sweep" jailed_report \
  "when jailed, a seam entry that is neither a pid nor a pid@scan is ignored, never a wider sweep"
check "AC7: the testing skill's Sweeper bullet and the comment above fence.SWEEPER state when the sweep ends and the seam's pid@scan entry" report \
  "the testing skill and the sweeper's own comment state when the sweep ends"
check "AC8: c0076's sweeper spec and the sweeper interlock spec still pass" \
  lune run tests/run -- tests/acceptance/c0076/sweeper.spec.luau tests/tooling/sweeper-interlock.spec.luau
check "AC9: only scans that stop something count toward the sweep's limit of fifty: fifty-one scans, ten of them stopping, end with the command's status (in AC5's real run)" real_cap
check "AC10: repo-fence's ALLOWED has an entry for the promoted spec, which names two guard settings as c0076's spec does" allowed

rm -rf "$rr_out"
finish

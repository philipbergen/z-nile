#!/usr/bin/env bash
# Acceptance checks for c0078. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0078 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0078"

# The spec's cases share one setup, so it runs once (here, outside `check`: list mode refuses it); a check then
# requires its named cases to exist in the spec and not fail, and the spec to have loaded.
signals_out=$(lune run tests/run -- "$A/jail-signals.spec.luau" 2>&1)
cases_in() { # $1: spec file, $2: its output, $3...: case-name prefixes that must exist and not fail
  local spec=$1 out=$2 c; shift 2
  [[ -f $spec ]] || { echo "missing $spec"; return 1; }
  if grep -q "could not load spec" <<<"$out"; then echo "$out"; return 1; fi
  grep -Eq "^[0-9]+ passed, [0-9]+ failed, 1 spec files$" <<<"$out" || { echo "$out" | tail -20; return 1; }
  for c in "$@"; do
    tr -d "\n\t" < "$spec" | grep -qF "it(\"$c" || { echo "$spec has no case starting \"$c\""; return 1; }
    if grep -F "FAIL" <<<"$out" | grep -qF ":: $c"; then grep -F -A3 ":: $c" <<<"$out"; return 1; fi
  done
}
signals() { cases_in "$A/jail-signals.spec.luau" "$signals_out" "$@"; }
jailed_cases() { # on macOS the jailed cases must have run, not returned early
  signals "$@" || return 1
  if [[ $(uname -s) == Darwin && ! -f .cache/c0078-signals/jailed-cases-ran ]]; then
    echo "the jailed cases did not run: run this check outside any other sandbox, so the specs are jailed"
    return 1
  fi
}

check "AC1: when jailed, a spec can't signal the run's top process, and can still signal what it started" jailed_cases \
  "when jailed, a spec can neither signal nor probe the run's top process" \
  "when jailed, a spec can still signal a process it started"
check "AC2: alive counts a refused probe as alive only when jailed, and a finished process as dead" signals \
  "alive counts a refused probe as alive only when jailed, and a finished process as dead"
check "AC3: the link probe says made, refused (only for Operation not permitted) or error, whatever sits at the old name" signals \
  "the link probe makes and removes a link where links are allowed" \
  "a regular file at the old predictable probe name does not make the probe say refused" \
  "a probe that fails for another reason is an error, not a refusal" \
  "when jailed, the link probe at the top of .cache says refused"
check "AC4: the testing skill states every guard as it now is" bash -c '
  s=.claude/skills/testing/SKILL.md
  for fact in "same-sandbox" "replace-file.pl" "cachepaths" "watchdog" "sweep" "99999"; do
    grep -qF "$fact" "$s" || { echo "the testing skill does not mention $fact"; exit 1; }
  done
  if grep -qF "the runner stops what is left in the specs'"'"' group when they end, but not this" "$s"; then
    echo "the skill still says processes that leave the group survive on macOS"; exit 1
  fi'

finish

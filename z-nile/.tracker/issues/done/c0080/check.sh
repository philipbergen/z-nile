#!/usr/bin/env bash
# Acceptance checks for c0080. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0080 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0080"

# The spec's cases share one fixture, so it runs once (here, outside `check`: list mode refuses it); a check then
# requires its named cases to exist in the spec and not fail, and the spec to have loaded.
conseq_out=$(lune run tests/run -- "$A/consequences.spec.luau" 2>&1)
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
conseq() { cases_in "$A/consequences.spec.luau" "$conseq_out" "$@"; }

check "AC1: done refuses a fixed answer without non-empty consequences, naming the finding; refuted answers need none" conseq \
  "a fixed answer without consequences is refused, naming the finding" \
  "a fixed answer with empty consequences is refused" \
  "fixed answers with consequences, and refuted answers without, get past the review check"
check "AC2: execute-raft Phase 4 runs the full gate first, gives the fixed format with consequences, and questions a twice-hit mechanism" bash -c '
  phase4=$(sed -n "/^## Phase 4/,/^## Phase 5/p" skills/zz-execute/SKILL.md)
  grep -qF "z-nile/check.sh --full" <<<"$phase4" || { echo "Phase 4 does not run the full gate before a review"; exit 1; }
  grep -qF "; consequences: " <<<"$phase4" || { echo "Phase 4'"'"'s fixed format has no consequences"; exit 1; }
  grep -qi "mechanism" <<<"$phase4" || { echo "Phase 4 says nothing about questioning a mechanism"; exit 1; }'
check "AC3: the review skill reviews the fix delta on a re-review and questions a mechanism hit again" bash -c '
  code=$(sed -n "/^## Code mode/,\$p" skills/zz-review/SKILL.md)
  grep -qi "fix delta" <<<"$code" || { echo "code mode does not review the fix delta"; exit 1; }
  grep -qi "mechanism" skills/zz-review/SKILL.md || { echo "the review skill says nothing about a mechanism hit again"; exit 1; }'
check "AC4: the overridden specs (c0001 lifecycle, c0038 deferred) pass" lune run tests/run -- \
  tests/acceptance/c0001/tracker-lifecycle.spec.luau tests/acceptance/c0038/deferred.spec.luau

finish

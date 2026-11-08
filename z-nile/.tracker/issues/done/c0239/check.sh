#!/usr/bin/env bash
# Acceptance checks for c0239. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0239 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0239"

check "AC1: zz-test holds the gate-by-step rule and the stop hook line, and the skills and templates restate each step's gate with the stale --full lines gone" lune run tests/run -- "$A/docs.spec.luau"
check "AC2: the raft template's RC0 runs the affected gate and no skill tells the author to run --full before the merge" lune run tests/run -- "$A/docs.spec.luau"
check "AC3: Phase 0 runs no gate, Phases 3 to 5 and the pre-PR step use the affected gate, and the merge's clean clone keeps --full" lune run tests/run -- "$A/docs.spec.luau"
check "AC4: done runs the affected gate on the done tree and rolls back on a red one (the overridden c0074/done-gate.spec), and doneGate answers affected" lune run tests/run -- "$A/done.spec.luau" tests/acceptance/c0074/done-gate.spec.luau
check "AC5: land still runs the full gate" lune run tests/run -- "$A/land.spec.luau"
check "AC6: scope names one project only for a non-empty selection inside it, from the whole change set, and ALL otherwise" lune run tests/run -- "$A/stop.spec.luau"
check "AC7: the stop hook runs the scoped affected gate only for a one-project answer" lune run tests/run -- "$A/stop.spec.luau"
# promoted specs are unchanged, except the six Overrides and c0239's own folder (c0165 lands first)
OVERRIDES='^z-nile/tests/acceptance/(c0239/|c0114/docs\.spec\.luau$|c0120/docs\.spec\.luau$|c0120/promote-home\.spec\.luau$|c0120/homes\.spec\.luau$|c0074/done-gate\.spec\.luau$|c0172/narrowed\.spec\.luau$)'
promoted_unchanged() {
  local out changed
  # every home's tests/acceptance (design review 004 F6.4), not only pickman's and z-nile's
  out=$(git -C "$ZN_ROOT" diff --name-only origin/main...HEAD 2>&1) ||
    { echo "cannot compare with origin/main: $out"; return 1; }
  out=$(printf '%s\n' "$out" | grep -E '^[^/]+/tests/acceptance/' || true)
  changed=$(printf '%s\n' "$out" | grep -Ev "$OVERRIDES" | grep -v '^$' || true)
  [[ -z $changed ]] || { echo "promoted specs changed: $changed"; return 1; }
}
# each Override equals the merge base with its named substitutions applied, byte for byte (design review 002 F3)
check "AC8: no promoted spec changes except the six Overrides and c0239's own folder, and each Override is the base with only its named substitutions" bash -c "$(declare -f promoted_unchanged); ZN_ROOT='$ZN_ROOT' OVERRIDES='$OVERRIDES'; promoted_unchanged && python3 '$A/narrow.py' '$ZN_ROOT'"

finish

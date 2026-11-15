#!/usr/bin/env bash
# Acceptance checks for c0293. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0293 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0293"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the root AGENTS.md is c0293's pipeline part (title, intro, the Non-negotiable paragraph, the stage table, the map), then the shared rules, and nothing else" lune run tests/run -- "$A/root.spec.luau"
# the carry reads the merge base, so it runs only on this line (and at `done`), never in the gate's promoted copy
check "AC2: the Non-negotiable paragraph and every shared rule are carried from the merge base byte for byte, in its order, and every other base paragraph is a named drop" env ZN_C0293_CARRY=1 lune run tests/run -- "$A/root.spec.luau"
check "AC3: each of the six project folders has its own AGENTS.md and a CLAUDE.md of @AGENTS.md, and the root keeps none of a project's parts" lune run tests/run -- "$A/homes.spec.luau"
check "AC4: SETUP.md says how Claude Code and the other agents find a project folder's AGENTS.md" lune run tests/run -- "$A/setup.spec.luau"
check "AC5: every rule the root drops is still stated in the skills, zz-rules or the README" lune run tests/run -- "$A/restated.spec.luau"
# promoted specs are unchanged, except the Overrides and c0293's own folder (c0112, c0136 and c0181 land first)
OVERRIDES='^z-nile/tests/acceptance/(c0293/|c0111/skill-docs\.spec\.luau$|c0115/docs\.spec\.luau$|c0120/docs\.spec\.luau$|c0183/docs\.spec\.luau$|c0184/docs\.spec\.luau$|c0112/docs\.spec\.luau$|c0136/docs\.spec\.luau$|c0181/docs\.spec\.luau$)'
promoted_unchanged() {
  local out changed
  # every home's tests/acceptance, not only z-nile's
  out=$(git -C "$ZN_ROOT" diff --name-only origin/main...HEAD 2>&1) ||
    { echo "cannot compare with origin/main: $out"; return 1; }
  out=$(printf '%s\n' "$out" | grep -E '^[^/]+/tests/acceptance/' || true)
  changed=$(printf '%s\n' "$out" | grep -Ev "$OVERRIDES" | grep -v '^$' || true)
  [[ -z $changed ]] || { echo "promoted specs changed: $changed"; return 1; }
}
check "AC6: no promoted spec changes except the Overrides and c0293's own folder" bash -c "$(declare -f promoted_unchanged); ZN_ROOT='$ZN_ROOT' OVERRIDES='$OVERRIDES'; promoted_unchanged"
# a change to a .md file selects no spec in an affected gate, so the specs that read AGENTS.md run here by name
check "AC7: every promoted spec that reads AGENTS.md passes, the Overrides included" lune run tests/run -- tests/acceptance/c0111/skill-docs.spec.luau tests/acceptance/c0114/docs.spec.luau tests/acceptance/c0115/docs.spec.luau tests/acceptance/c0115/absence.spec.luau tests/acceptance/c0116/docs.spec.luau tests/acceptance/c0117/docs.spec.luau tests/acceptance/c0120/docs.spec.luau tests/acceptance/c0165/docs.spec.luau tests/acceptance/c0183/docs.spec.luau tests/acceptance/c0184/docs.spec.luau tests/acceptance/c0191/docs.spec.luau tests/acceptance/c0112/docs.spec.luau tests/acceptance/c0136/docs.spec.luau tests/acceptance/c0181/docs.spec.luau tests/acceptance/c0194/docs.spec.luau

finish

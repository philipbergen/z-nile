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
# promoted specs are unchanged, except c0293's Overrides, c0172's narrowed.spec (one digest, F2) and the Overrides of the
# members of c0293's raft, which z-raft may fold with it (a mate overriding one of c0293's own files is a conflict
# z-raft must not fold: c0293.md, Design). c0112, c0136 and c0181 land first.
OVERRIDES='^z-nile/tests/acceptance/(c0293/|c0111/skill-docs\.spec\.luau$|c0115/docs\.spec\.luau$|c0120/docs\.spec\.luau$|c0183/docs\.spec\.luau$|c0184/docs\.spec\.luau$|c0112/docs\.spec\.luau$|c0136/docs\.spec\.luau$|c0181/docs\.spec\.luau$|c0172/narrowed\.spec\.luau$)'
mates_overrides() { # the promoted paths named on the Overrides lines of the other members of c0293's raft
  local raft dir f p
  f=$("$ZN_ROOT/zn" find c0293 2>/dev/null) || return 0
  raft=$(sed -n 's/^raft: *//p' "$ZN_ROOT/$f/c0293.md" 2>/dev/null | head -1)
  [[ -n $raft ]] || return 0
  "$ZN_ROOT/zn" members "$raft" | while read -r dir; do
    [[ $dir == */c0293 ]] && continue
    awk '/^Overrides:/{on=1} /^## /{on=0} on' "$ZN_ROOT/$dir/$(basename "$dir").md" | grep -oE '`[^`]*tests/acceptance/[^`]*`' | tr -d '`' | while read -r p; do
      [[ $p == tests/* ]] && p="${dir%%/*}/$p"
      echo "$p"
    done
  done
}
promoted_unchanged() {
  local out changed mates
  # every home's tests/acceptance, not only z-nile's
  out=$(git -C "$ZN_ROOT" diff --name-only origin/main...HEAD 2>&1) ||
    { echo "cannot compare with origin/main: $out"; return 1; }
  out=$(printf '%s\n' "$out" | grep -E '^[^/]+/tests/acceptance/' || true)
  mates=$(mates_overrides)
  changed=$(printf '%s\n' "$out" | grep -Ev "$OVERRIDES" | grep -vxF -f <(printf '%s\n' "$mates" "") | grep -v '^$' || true)
  [[ -z $changed ]] || { echo "promoted specs changed: $changed"; return 1; }
}
check "AC6: no promoted spec changes except the Overrides (each the base with only its named substitutions) and c0293's own folder" bash -c "$(declare -f mates_overrides promoted_unchanged); ZN_ROOT='$ZN_ROOT' OVERRIDES='$OVERRIDES'; promoted_unchanged"
check "AC6: the Overrides are the smallest narrowing (check time only)" env ZN_C0293_CARRY=1 lune run tests/run -- "$A/narrowed.spec.luau"
# a change to a .md file selects no spec in an affected gate, so the specs that read AGENTS.md run here by name. The list
# is computed at check time (readers that land later join it) and refuses to be short: the specs this design counts must
# all be in it, and the four that land first (c0112, c0136, c0181, c0194) are named through $ZN_ROOT, so a path that
# does not exist yet is not a path this check.sh names (zz-test, Acceptance checks).
agents_readers() {
  local want got id f specs=() missing=() d="$ZN_ROOT/z-nile/tests/acceptance"
  got=$(git -C "$ZN_ROOT" grep -lF AGENTS.md -- '*/tests/acceptance/*.spec.luau' | grep -v '/c0293/' || true)
  for f in c0111/skill-docs c0114/docs c0115/docs c0115/absence c0116/docs c0117/docs c0120/check-paths c0120/docs c0120/finished c0183/docs c0184/docs c0191/docs c0239/docs c0112/docs c0136/docs c0181/docs c0194/docs; do
    grep -qF "z-nile/tests/acceptance/$f.spec.luau" <<<"$got" || missing+=("$f")
  done
  [[ ${#missing[@]} -eq 0 ]] || { echo "the readers of AGENTS.md no longer include: ${missing[*]}"; return 1; }
  while read -r f; do specs+=("$ZN_ROOT/$f"); done <<<"$got"
  specs+=("$d/c0172/narrowed.spec.luau")
  lune run tests/run -- "${specs[@]}"
}
check "AC7: every promoted spec that reads AGENTS.md (found by git grep, at least the 17 this design counts) passes, the Overrides and c0172's narrowed.spec included" agents_readers

finish

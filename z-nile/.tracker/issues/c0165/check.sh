#!/usr/bin/env bash
# Acceptance checks for c0165. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0165 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0165"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
S="$A/select.spec.luau"
P="$A/plan.spec.luau"
D="$A/store.spec.luau"
G="$A/gate.spec.luau"
check "AC1: one predicate decides both selection and fingerprints, and the moved rules keep their outcomes" lune run tests/run -- "$S"
check "AC2: a spec's fingerprint changes for each kind of input (tracker paths through explicit entries, the gate mode) and for nothing else" lune run tests/run -- "$S"
check "AC3: reuseplan.decide gives the table's action for every row, and a gone or reused pid doesn't hold" lune run tests/run -- "$P"
check "AC4: the db claims by insert or compare-and-swap with one winner, records only into its own or an absent row, round-trips any text, and open answers nil with a reason" lune run tests/run -- "$D"
check "AC5: through the orchestrator and the gate, same content reuses every spec, an edit reruns exactly its selection, concurrent runs run each spec once, a killed owner is taken over and its runner dies, only an exit of 0 records passes, and reuse off runs everything" lune run tests/run -- "$G"
check "AC6: the runner writes every file's cases and results in process and concurrently, marks a dead worker's file not loaded, and its output and exit code are unchanged" lune run tests/run -- "$A/results.spec.luau"
check "AC7: --full runs every spec, --full --reuse skips only on a full record of the same content digest (done's staged tree included), a tree that changed records nothing, the digest ignores spend.md and ignored files, and the reads write nothing to git and fail closed" lune run tests/run -- "$A/digest.spec.luau" "$G"
check "AC8: a seeded graph miss (a tracker file's too) fails the full gate, is recorded in the db and printed for inputs.tsv, affected --learned then selects it and a bare call does not; only unselected failures that pass on the base are learned, within a budget" lune run tests/run -- "$P" "$G"
check "AC9: inputs.tsv parses comments, blank lines, files and folders, and refuses the whole file on a malformed line" lune run tests/run -- "$S"
check "AC10: the skills, the templates, AGENTS.md and .gitignore say the new gate modes and name the db" lune run tests/run -- "$A/docs.spec.luau"
# promoted specs (every project's tests/acceptance) are unchanged, except the four Overrides and c0165's own folder
OVERRIDES='^z-nile/tests/acceptance/(c0165/|c0120/docs\.spec\.luau$|c0114/docs\.spec\.luau$|c0120/homes\.spec\.luau$|c0120/promote-home\.spec\.luau$)'
promoted_unchanged() {
  local out changed
  # git's own failure (no origin/main, a bad pathspec) is red, never filtered away
  out=$(git -C "$ZN_ROOT" diff --name-only origin/main...HEAD -- "$ZN_ROOT/pickman/tests/acceptance" "$ZN_ROOT/z-nile/tests/acceptance" 2>&1) ||
    { echo "cannot compare with origin/main: $out"; return 1; }
  changed=$(printf '%s\n' "$out" | grep -Ev "$OVERRIDES" | grep -v '^$' || true)
  [[ -z $changed ]] || { echo "promoted specs changed: $changed"; return 1; }
}
check "AC11: no promoted spec changes except the four Overrides and c0165's own folder" promoted_unchanged
# each Override changes only its RC0 line: on the lines that call the template's gate (`z-nile/check.sh" --project <p>
# --affected`) and nowhere else, "--affected" and "(affected)" read back as "--full" and "(full)"; the file is then main's
# byte for byte, so everything else it pins stays (design review 001 F10: a global substitution let line 93's
# `[--full]` pin move too)
overrides_narrowed() {
  local f old new
  for f in z-nile/tests/acceptance/c0120/docs.spec.luau z-nile/tests/acceptance/c0114/docs.spec.luau \
    z-nile/tests/acceptance/c0120/homes.spec.luau z-nile/tests/acceptance/c0120/promote-home.spec.luau; do
    old=$(git -C "$ZN_ROOT" show "origin/main:$f" 2>&1) || { echo "cannot read origin/main:$f: $old"; return 1; }
    new=$(sed -E -e '/z-nile\/check\.sh" --project [^ ]+ --affected/{s/--affected/--full/;s/\(affected\)/(full)/;}' "$ZN_ROOT/$f") || return 1
    [[ $new == "$old" ]] || { echo "$f changes more than its RC0 line"; return 1; }
    grep -Eq -- 'z-nile/check\.sh" --project [^ ]+ --affected' "$ZN_ROOT/$f" || { echo "$f does not pin the --affected RC0 line"; return 1; }
  done
}
check "AC12: each Override changes only its RC0 line, to --affected" overrides_narrowed

finish

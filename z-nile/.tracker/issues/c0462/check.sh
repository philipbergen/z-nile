#!/usr/bin/env bash
# Acceptance checks for c0462. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0462 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0462"
R="$A/rewrite-list.txt"
RS="$A/rewrite-list-slow.txt"

# Work outside `check` is limited to running a spec through `tests/run`, `./zn members` and other cheap reads.
check "AC1: t counts one per matcher call and per t.assert, none for expect alone or a helper" lune run tests/run -- "$A/count.spec.luau"
check "AC2: the runner fails a case with no assertion (file and case named) when the check applies, not in a .cache fixture without the flag, reaches workers, exempts a listed item, exits 2 on a bad list" lune run tests/run -- "$A/fixture.spec.luau"
check "AC3: the pure rules read an item's id, refuse look-alikes and malformed lists, and decide the gate rerun" lune run tests/run -- "$A/vacuous.spec.luau"
check "AC4: the checked-in list is well formed, sorted, unique and excludes c0462" lune run tests/run -- "$A/exempt.spec.luau"

# AC5 (check.sh only: a promoted spec equal to the tree would fail the day a new item's specs arrive)
check "AC5: the exempt list equals what the writer gives for this tree" lune run "$ZN_ROOT/z-nile/vacuous-exempt" -- --check

# AC6 (check.sh only): the landing rule on four histories of a throwaway repository under .cache
ac6() {
  local d
  d="$PWD/.cache/c0462-ac8"
  rm -rf "$d" && mkdir -p "$d" || return 1
  git init -q -b main "$d" || return 1
  [[ $(git -C "$d" rev-parse --show-toplevel) == "$(cd "$d" && pwd -P)" ]] || { echo "not the fixture repo"; return 1; }
  local c="git -C $d -c user.name=dev -c user.email=dev@example.invalid"
  mkdir -p "$d/pickman/.tracker/issues/c1" "$d/snake/tests/unit" "$d/z-nile/tests"
  echo a > "$d/pickman/.tracker/issues/c1/c1.md"; echo a > "$d/z-nile/tests/vacuous-exempt.txt"
  git -C "$d" add -A && $c commit -qm base || return 1
  local base; base=$(git -C "$d" rev-parse HEAD)
  local rule=(lune run "$ZN_ROOT/z-nile/vacuous-exempt" -- --gate-needed)
  echo b >> "$d/pickman/.tracker/issues/c1/c1.md"; git -C "$d" add -A; $c commit -qm tracker
  [[ $(cd "$d" && "${rule[@]}" "$base" HEAD) == no ]] || { echo "tracker-only commit must not rerun the gate"; return 1; }
  echo b > "$d/snake/tests/unit/x.spec.luau"; git -C "$d" add -A; $c commit -qm spec
  [[ $(cd "$d" && "${rule[@]}" "$base" HEAD) == yes ]] || { echo "a spec change must rerun the gate"; return 1; }
  local second; second=$(git -C "$d" rev-parse HEAD)
  echo b > "$d/z-nile/tests/helper.luau"; git -C "$d" add -A; $c commit -qm helper
  [[ $(cd "$d" && "${rule[@]}" "$second" HEAD) == yes ]] || { echo "a file under tests/ must rerun the gate"; return 1; }
  [[ $(cd "$d" && "${rule[@]}" HEAD HEAD) == no ]] || { echo "no commits must not rerun the gate"; return 1; }
  (cd "$d" && "${rule[@]}" "$base" HEAD >/dev/null) || { echo "a resolvable range must exit 0"; return 1; }
  local bad
  bad=$(cd "$d" && "${rule[@]}" nosuchref HEAD 2>/dev/null)
  if [[ -n $bad ]] || (cd "$d" && "${rule[@]}" nosuchref HEAD >/dev/null 2>&1); then echo "an unknown ref must exit non-zero with empty stdout"; return 1; fi
  rm -rf "$d"
}
check "AC6: the writer says to rerun the gate only for a spec or tests/ change, and fails on an unknown ref" ac6

check "AC7: zz-test and the lesson state the rule and the review-only residue" lune run tests/run -- "$A/docs.spec.luau"

# AC8 (check.sh only): every listed case still exists and passes under its home's runner with the check on
ac8() {
  grep -q -e "--require-assertions" "$ZN_ROOT/z-nile/tests/run.luau" || { echo "the runner has no zero-assertion check yet: a clean run would prove nothing"; return 1; }
  [[ -f $R ]] || { echo "$R is not here"; return 1; }
  local pairs home file files out
  pairs=$(grep -v '^#' "$R" | grep -v '^$' | sed -E 's/ :: .*$//' | sort -u) || true
  [[ -n $pairs ]] || { echo "the list read no lines"; return 1; }
  # bash 3.2 has no associative arrays: one pass per home, its files read from the sorted pairs
  for home in $(printf '%s\n' "$pairs" | sed -E 's/:.*$//' | sort -u); do
    files=()
    while IFS= read -r file; do files+=("$file"); done < <(printf '%s\n' "$pairs" | grep "^$home: " | sed -E 's/^[^:]*: //')
    ((${#files[@]} > 0)) || { echo "no files for $home"; return 1; }
    out="$ZN_ROOT/$home/.cache/c0462-results.json"
    rm -f "$out"
    (cd "$ZN_ROOT/$home" && PICKMAN_RESULTS="$out" lune run tests/run -- "${files[@]}") || return 1
    lune run "$A/listed-cases.luau" "$R" "$home" "$out" || return 1
  done
}
# the slow-tier lines are not run here (about 7 minutes of wall time at every finish): each must still be a case of its file.
# That they pass with the check on is Observed (OC1): z-nile/check.sh --slow at the merge, recorded in the Verification log
# (--full does not run the slow tier)
ac8slow() {
  local line file case n=0
  [[ -f $RS ]] || { echo "$RS is not here"; return 1; }
  while IFS= read -r line; do
    [[ $line == \#* || -z $line ]] && continue
    file=${line#*: }; file=${file%% :: *}; case=${line#* :: }
    grep -qF -e "it(\"$case\"" "$ZN_ROOT/z-nile/$file" || { echo "deleted or renamed slow case: $file :: $case"; return 1; }
    n=$((n + 1))
  done < "$RS"
  ((n > 0)) || { echo "the slow list read no lines"; return 1; }
}
ac8both() { ac8 && ac8slow; }
check "AC8: every listed case still exists and passes with the zero-assertion check on (slow-tier cases: still exist)" ac8both


finish

#!/usr/bin/env bash
# Acceptance checks for c0269. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0269 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0269"

# AC1: the exact texts are claims about today's two files, so they live here and not in a promoted case (a later reword
# that keeps the rule must not turn the gate red); after the raft's `done` this file is not rerun
has() { grep -qF -- "$2" "$1" || { echo "$1 does not say: $2"; return 1; }; }
hasnt() { ! grep -qF -- "$2" "$1" || { echo "$1 still says: $2"; return 1; }; }
texts_stand() {
  local d=tests/acceptance/c0074/done-gate.spec.luau c=tests/acceptance/c0080/consequences.spec.luau rc=0
  has $d '`tracker.sh done` runs the affected gate on the final tree' || rc=1
  has $d 't.spec("c0800 done runs the affected gate after promotion"' || rc=1
  has $d 'it("done runs the affected gate on the promoted, moved tree, then commits"' || rc=1
  has $d 'it("the gate decision: affected, unless inside a spec run without the switch"' || rc=1
  has $c '(so done skips the gate, c0800)' || rc=1
  hasnt $d 'runs the full gate on the final tree' || rc=1
  hasnt $d 'done runs the full gate' || rc=1
  hasnt $d 'the gate decision: full' || rc=1
  hasnt $c 'skips the full gate' || rc=1
  return $rc
}
check "AC1: the five new texts stand in the two specs and the five old ones are gone" texts_stand
check "AC2: no spec file under z-nile/tests repeats the old rule in a title, a comment or a string, the scan finds each form, and inputs.tsv declares the reads" lune run tests/run -- "$A/titles.spec.luau"
check "AC3: the two edited specs still pass" lune run tests/run -- tests/acceptance/c0074/done-gate.spec.luau tests/acceptance/c0080/consequences.spec.luau
# the published main AC4 compares against, printed outside `check` (a passing command's output is hidden): a swapped origin is review's to catch
echo "AC4 base: $(git -C "$ZN_ROOT" ls-remote --get-url origin) refs/heads/main"
check "AC4: each file is its merge base plus only the five named substitutions, and inputs.tsv keeps its rows and gains the one" python3 "$A/narrow.py" "$ZN_ROOT"
# AC5: the order the rename's hand-off rests on, read through the tracker (a claim about today's items, so not a spec);
# the path `find` prints is home-relative (z-design/check-paths-from-the-home), so it is used as it is
c0241_waits() { local d; d=$(../zn find c0241) && grep -qE '^depends_on:.*c0269' "$d/c0241.md"; }
check "AC5: c0241 (the re-prep that requotes c0180's digest of done-gate.spec) depends on c0269" c0241_waits

finish

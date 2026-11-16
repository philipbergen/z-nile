#!/usr/bin/env bash
# Acceptance checks for c0193. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0193 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0193"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: scan.advance returns the next position only when it is past the current one, and raises, naming both, when it stays, goes back or is not a number" \
  lune run tests/run -- "$A/scan.spec.luau"
check "AC2: hostile.texts lists every text of up to n characters over an alphabet, in a fixed order with none twice, and refuses an empty, repeated or oversized request" \
  lune run tests/run -- "$A/texts.spec.luau"
check "AC3: hostile.finishes passes scanners that return or refuse some texts and fails one that never returns within its limit (naming the case and the texts it stopped in), one whose witness fails or that raised on every non-empty text (it never ran its work), a crash (naming its code), a bad limit, an empty text list and a bad case, leaving no folder" \
  lune run tests/run -- "$A/finishes.spec.luau"
check "AC4: loops.find proves a loop only when it does not read text, its own top level steps its variable by a positive literal in the condition's direction (or through one whole scan.advance call) before any continue, nothing else in the body resets or steps back that variable, the bound is a number, a name or #name that the body never writes, and its end is found by structure; it fails closed on any other shape (the c0193 incident's loop included)" \
  lune run tests/run -- "$A/loops.spec.luau"
check "AC5: loops.problems requires every loop that is not proven to be the next entry of its file's reviewed list with a reason, a loop that reads text to name its sweep, and reports stale and out-of-order entries, each naming the file, line, lesson and fix" \
  lune run tests/run -- "$A/problems.spec.luau"
check "AC6: every loop in the tooling's files is proven or on the reviewed list, and no entry is stale (also as the executor-written tests/meta case that is the lesson's enforcing ref)" \
  lune run tests/run -- "$A/tree.spec.luau" "$ZN_ROOT/z-nile/tests/meta/scanning-loops.spec.luau"
check "AC7: every text scanner of the engine and the library finishes on every hostile text within the limit, each case reaching its scanner's work (a witness), the six named cases exist, and the alphabet holds every one-character literal its module compares with by == or ~=" \
  bash -c 'lune run tests/run -- "$0" && for n in graph.stripComments paths.rewrite ids.rewritePaths ids.rewrite skills.oldLessonIds skills.oldNames; do grep -q "name = \"$n\"" "$ZN_ROOT/z-nile/tests/lib/scanners.luau" || { echo "no scanners case $n"; exit 1; }; done' "$A/scanners.spec.luau"
check "AC8: zz-arch states the rule (a text-reading loop is always listed and swept) and its checks, and zz-test tells spec writers about hostile inputs" \
  lune run tests/run -- "$A/docs.spec.luau"
check "AC9: the lesson is short, keeps the check question and names its enforcing files, and it and its harvest entry pass ./zn lessons --check and --uncovered, with c0193 on its sources line" \
  bash -c 'L=skills/zz-arch/lessons/scanning-loops-advance.md; [ "$(wc -l < "$L")" -le 20 ] && grep -q "^when: both" "$L" && grep -q "^check: .*leave its position where it was" "$L" && E=$(grep "^\*\*Enforced by\*\*" "$L") && for f in z-nile/engine/scan.luau z-nile/tests/lib/loops.luau z-nile/tests/lib/scanners.luau z-nile/tests/lib/hostile.luau; do case "$E" in *"$f"*) ;; *) echo "the lesson does not name $f"; exit 1;; esac; done && grep -q "PR #125" "$L" && grep -q "14 h" "$L" && "$ZN_ROOT/zn" lessons --check && "$ZN_ROOT/zn" lessons --uncovered c0193 && "$ZN_ROOT/zn" lessons --skill zz-arch --full scanning-loops-advance | grep -E "^sources:.*c0193" > /dev/null'

finish

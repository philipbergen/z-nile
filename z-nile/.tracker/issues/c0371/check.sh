#!/usr/bin/env bash
# Acceptance checks for c0371. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0371 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0371"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the scan reads a root cd across lines until its group or script closes (comments, line-end parentheses, the quote idioms), search helpers' quoted arguments, code spans, echo and printf messages and text-only for lists as prose, and still reports a really missing path; the live tree passes" \
  lune run tests/run -- "$A/check-paths-homes.spec.luau"

check "AC2: a path is compared with Touched modules by its repository-relative form, one convention per document read from its text, and a path that climbs above the checkout is never exempt (c0141's outcome)" \
  lune run tests/run -- "$A/touched-from-home.spec.luau"

check "AC3: c0120's check-paths spec takes its scan from the module in its folder and defines no scanner of its own (c0141's outcome)" \
  lune run tests/run -- "$A/uses-module.spec.luau"

check "AC4: c0120's check-paths spec passes on the live tree with the check.sh of f0201, c0292 and c0193 as they are" \
  lune run tests/run -- tests/acceptance/c0120/check-paths.spec.luau

check "AC5: the branch edits no other item's check.sh (only this item's and the raft's)" \
  bash -c 'cd "$ZN_ROOT" && base=$(git merge-base origin/main HEAD) || { echo "no origin/main to compare with"; exit 1; }
    other=$(git diff --name-only "$base" HEAD -- ":(glob)**/check.sh" | grep -v -e "/c0371/" -e "/rafts/")
    [[ -z $other ]] || { echo "check.sh files changed: $other"; exit 1; }'

check "AC6: zz-test says how the scan reads a root cd, a search helper, a code span, an echo or printf message and a text-only for list; z-design says a Touched list has one convention; tests/inputs.tsv declares c0371's live spec" \
  bash -c 'F="$ZN_ROOT/z-nile/skills/zz-test/SKILL.md"
    for w in "after \`cd \"\$ZN_ROOT\"\` from the repository root" "the quoted arguments of a search helper the check defines" "a word inside a code span" "an \`echo\` or \`printf\` message in command position" "the list of a \`for\` loop that only matches text"; do
      grep -qF -- "$w" "$F" || { echo "zz-test does not say: $w"; exit 1; }
    done
    grep -qF "in one convention for the whole list" "$ZN_ROOT/z-nile/skills/z-design/SKILL.md" || { echo "z-design does not say a Touched list has one convention"; exit 1; }
    grep -qxF "$(printf "tests/acceptance/c0371/check-paths-homes.spec.luau\t*")" tests/inputs.tsv || { echo "tests/inputs.tsv has no line for the c0371 live spec"; exit 1; }'

finish

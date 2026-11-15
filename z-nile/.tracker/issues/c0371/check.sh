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
check "AC1: a Touched entry covers a path written as a repo path or from the home; a path covered by no entry is reported, also when it exists elsewhere; a command after cd to the repository root is read from the root until its subshell closes; a word in a code span of quoted text and an echo's message are prose" \
  lune run tests/run -- "$A/check-paths-homes.spec.luau"

check "AC2: c0120's check-paths spec passes on the live tree (f0201's and c0292's checks among its items), and it reads the scan from the module the new cases share" \
  bash -c 'lune run tests/run -- tests/acceptance/c0120/check-paths.spec.luau \
    && grep -qF "check-paths-scan" tests/acceptance/c0120/check-paths.spec.luau \
    && test -f tests/acceptance/c0120/check-paths-scan.luau'

check "AC3: the branch edits no other check.sh (those of f0201 and c0292 stay as they are): only this item and its raft write check.sh files" \
  bash -c 'cd "$ZN_ROOT" && base=$(git merge-base origin/main HEAD) || { echo "no origin/main to compare with"; exit 1; }
    other=$(git diff --name-only "$base" HEAD -- ":(glob)**/check.sh" | grep -v -e "/c0371/" -e "/rafts/")
    [[ -z $other ]] || { echo "check.sh files changed: $other"; exit 1; }'

check "AC4: zz-test says how the scan reads a Touched entry, a cd to the repository root, a code span and an echo" \
  bash -c 'F="$ZN_ROOT/z-nile/skills/zz-test/SKILL.md"
    for w in "repo path or a path from the home" "after \`cd \"\$ZN_ROOT\"\` is read from the repository root" "inside a code span" "an \`echo\` message"; do
      grep -qF -- "$w" "$F" || { echo "zz-test does not say: $w"; exit 1; }
    done'

finish

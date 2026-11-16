#!/usr/bin/env bash
# Acceptance checks for c0322. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0322 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0322"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: every row ./zn commit and ./zn done record for a commit has that commit's first line as its subject whatever the session reading says, the reading's tokens, AI seconds and model go on the first row only (a named model wins on every row), and the session's note is the commit's last trailer, after one Issue line per row" \
  lune run tests/run -- "$A/bind-subject.spec.luau"
check "AC2: the CLI builds a commit's rows with one call on the commit's own message and the session's reading, builds no subject of its own, prints the note and hands it to the one trailer call, and finish's own row is as it was" \
  lune run tests/run -- "$A/wiring.spec.luau"
# commit-phase is slow-tier (z-nile/tests/slow.tsv, about 16 s): no gate runs it, and it is the spec this issue turns
# green, so this line is its one run (lessons zz-test/check-sh-never-runs-the-slow-tier, the c0302 note, and
# z-design/guards-name-slow-tier-specs). That this branch left the file alone is a comparison with the merge base,
# read-only and never promoted: other items edit other cases of that file. It fails closed with no origin/main.
unedited_and_green() {
  local f=tests/acceptance/c0084/commit-phase.spec.luau base
  base="$(git merge-base origin/main HEAD)" && [[ -n $base ]] || { echo "no merge base with origin/main"; return 1; }
  git diff --quiet "$base" HEAD -- "$f" || { echo "this branch edits $f"; return 1; }
  git diff --quiet HEAD -- "$f" || { echo "$f has uncommitted edits"; return 1; }
  lune run tests/run -- "$1/expectation.spec.luau" && lune run tests/run -- "$f"
}
check "AC3: c0084's commit-phase.spec still expects the plain bind subject, this branch does not edit that file, and it passes, its case 'done records its own commit as deliver' included" \
  unedited_and_green "$A"

finish

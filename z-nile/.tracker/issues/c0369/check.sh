#!/usr/bin/env bash
# Acceptance checks for c0369. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0369 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0369"
# c0283's specs the same way: in its item folder (`zn find`) until its raft's `./zn done` promotes them
P="$PWD/$("$ZN_ROOT/zn" find c0283 2>/dev/null)/acceptance" # find prints a path from the home ac.sh cds to
[[ -d $P ]] || P="$PWD/tests/acceptance/c0283"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.

check "AC1: the place is the one worktree with a design of its own and no matching approval, else origin/main, and the retry's is the unpublished record" \
  lune run tests/run -- "$A/place.spec.luau"
check "AC2: from the main checkout or a worktree behind main, one approve records and publishes a merged design and writes no checkout" \
  lune run tests/run -- "$A/approve.spec.luau"
check "AC3: an unmerged design is approved in its prep worktree and its branch pushed, and a merged prep left behind is not taken" \
  lune run tests/run -- "$A/approve.spec.luau"
check "AC4: two unapproved designs are refused by name, and the one the command runs inside is taken" \
  lune run tests/run -- "$A/approve.spec.luau"
check "AC5: a failed publish or push keeps the record and names approve --publish, which finds it from anywhere" \
  lune run tests/run -- "$A/approve.spec.luau"
check "AC6: the skills, AGENTS.md and the tooling's refusals state the one command from anywhere" \
  lune run tests/run -- "$A/docs.spec.luau"
check "AC7: the specs that read approve stay green and the real tree audits and lessons-checks clean" \
  bash -c '"$ZN_ROOT/zn" audit && "$ZN_ROOT/zn" lessons --check && lune run tests/run -- "$1/approval.spec.luau" "$1/publish.spec.luau" "$1/approve.spec.luau" "$1/docs.spec.luau" tests/tooling/approve.spec.luau tests/tooling/approve-publish.spec.luau tests/tooling/readycheck.spec.luau tests/tooling/work.spec.luau' _ "$P"

finish

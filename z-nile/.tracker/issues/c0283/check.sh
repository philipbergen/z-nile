#!/usr/bin/env bash
# Acceptance checks for c0283. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0283 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0283"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.

check "AC1: the approval check, the frozen list's parser and renderer and the doors' one rule hold" \
  lune run tests/run -- "$A/approval.spec.luau"
check "AC2: ./zn approve records the human and the design hash as the human's tracker: approve commit, is refused in every agent session first of all, and refuses each of its other cases for its own reason" \
  lune run tests/run -- "$A/approve.spec.luau"
check "AC3: ./zn status <id> prepared needs a current approval (redesign, check.sh, a stop, a raft's move, ZN_DISPATCH)" \
  lune run tests/run -- "$A/approve.spec.luau"
check "AC4: fold, new raft and ready refuse, raft-plan skips and audit errors on an unapproved prepared issue unless the base's frozen list covers its design" \
  lune run tests/run -- "$A/approve.spec.luau" "$A/freeze.spec.luau"
check "AC5: ./zn provenance freeze writes the frozen list once from a worktree, and audit holds a listed issue to its listed design" \
  lune run tests/run -- "$A/freeze.spec.luau"
check "AC6: the dispatcher's prep gate never merges, keeps its reasons and adds the approve suffix" \
  lune run tests/run -- "$A/dispatch.spec.luau"
check "AC7: zz-rules, z-design, the README, AGENTS.md, .models.toml and the usage state the approval rules" \
  lune run tests/run -- "$A/docs.spec.luau"
check "AC8: the committed frozen list matches the tree, the real tree audits and lessons-checks clean, and the overridden promoted specs pass in their narrowed form" \
  bash -c '"$ZN_ROOT/zn" provenance freeze --check && "$ZN_ROOT/zn" audit && "$ZN_ROOT/zn" lessons --check && lune run tests/run -- tests/acceptance/c0053/commands-claim.spec.luau tests/acceptance/c0053/commands-prep.spec.luau tests/acceptance/c0053/commands-start.spec.luau tests/acceptance/c0116/claims.spec.luau tests/acceptance/c0116/issue-design.spec.luau tests/acceptance/c0116/docs.spec.luau tests/acceptance/c0117/dispatch.spec.luau tests/acceptance/c0117/control-cli.spec.luau tests/tooling/dispatch-guards.spec.luau tests/tooling/dispatch-texts.spec.luau tests/acceptance/c0161/review-gate.spec.luau tests/acceptance/c0161/review-raft.spec.luau tests/acceptance/c0161/review-read.spec.luau'

finish

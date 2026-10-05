#!/usr/bin/env bash
# Acceptance checks for c0081. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0081 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0081"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `tracker.sh members` and other cheap reads; everything else goes inside `check`.
check "AC1: ids parses the counter strictly, numbers by one, plans and rewrites in one pass" \
  lune run tests/run -- "$A/ids.spec.luau"
check "AC2: new, new raft, emergent issues and renumber take and raise origin's counter; legacy without it" \
  lune run tests/run -- "$A/allocate.spec.luau"
check "AC3: compact refuses busy or unsound trees, else renumbers everything from 0001 in one commit" \
  lune run tests/run -- "$A/compact.spec.luau"
check "AC4: a stale tree never publishes; remap brings a busy branch onto the new ids and merges origin/main" \
  lune run tests/run -- "$A/remap.spec.luau" "$A/publish-guard.spec.luau"
check "AC5: the tracker skill documents the counter, the legacy rule, compaction and remap" \
  lune run tests/run -- "$A/skill-doc.spec.luau"
check "AC6: tracker/next is in the real tree, real ids pin through renamed, and overridden specs pass" \
  lune run tests/run -- tests/acceptance/c0001/tracker-lifecycle.spec.luau tests/acceptance/c0005/worktree.spec.luau \
  tests/acceptance/c0008/done-order.spec.luau tests/acceptance/c0038/deferred.spec.luau \
  tests/acceptance/c0044/naming.spec.luau tests/acceptance/c0045/workstreams.spec.luau \
  tests/acceptance/c0046/launch.spec.luau tests/acceptance/c0050/start-depends.spec.luau \
  tests/acceptance/c0052/skill-doc.spec.luau tests/acceptance/c0043/rounds.spec.luau \
  tests/tooling/repo-fence.spec.luau "$A/next-file.spec.luau" "$A/renamed.spec.luau"

finish

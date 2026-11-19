#!/usr/bin/env bash
# Acceptance checks for d0383. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/d0383 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/d0383"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: a watch-kick from any worktree starts the net in the main checkout's standing worktree, returns only once the net is known to have started, reports a failed, killed or silent net on stderr with a non-zero exit, keeps its files per kick in the main checkout, and passes no variable to the net's suite" \
  lune run tests/run -- "$A/watch-net-kick.spec.luau"
check "AC2: at most one net runs per repository: a second kick prints already running and exits 0, a stale or reused-pid lock is taken over, and a rerun request is honoured exactly once" \
  lune run tests/run -- "$A/watch-net-lock.spec.luau"
check "AC3: the reaper leaves the detached net's tree alone while it is younger than its own limit, and no other orphan" \
  lune run tests/run -- "$A/watch-net-reaper.spec.luau"
check "AC4: when a commit on origin/main that changes something outside the tracker folders is more than 24 hours newer than the last pass commit, watch-kick prints the no-pass line and the board shows it; tracker-only commits never count; the limit is one constant" \
  lune run tests/run -- "$A/watch-net-stale.spec.luau"
check "AC5: the specs at risk pass: watch, watch-map, board, board-review, cache-paths, the reaper's, the two loop scans, board-refresh, readers, lock-start-ids and reuse" \
  lune run tests/run -- tests/tooling/watch.spec.luau tests/tooling/watch-map.spec.luau tests/tooling/board.spec.luau \
  tests/tooling/board-review.spec.luau tests/acceptance/c0077/cache-paths.spec.luau tests/acceptance/c0191/reap.spec.luau \
  tests/tooling/bounded-review.spec.luau tests/acceptance/c0193/tree.spec.luau tests/meta/scanning-loops.spec.luau \
  tests/acceptance/c0070/board-refresh.spec.luau tests/acceptance/c0278/readers.spec.luau \
  tests/tooling/lock-start-ids.spec.luau tests/acceptance/c0127/reuse.spec.luau

finish

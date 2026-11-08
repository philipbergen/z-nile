#!/usr/bin/env bash
# Acceptance checks for c0118. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home: the root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0118 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0118"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: every effective status has one column (ready or run by the raft's branch), bands, UTC weeks, rounds once, both charts' series" \
  lune run tests/run -- "$A/view.spec.luau"
check "AC2: history dates each issue's and raft's first arrival in done/ in UTC, across root moves, never across a compaction" \
  lune run tests/run -- "$A/history.spec.luau"
check "AC3: the model has a tab per project, columns, bands, done times and ages, rounds with members and retired rafts, two charts per project, card facts" \
  lune run tests/run -- "$A/model.spec.luau"
check "AC4: the page opens on the first project's Board; the done window, bands, range, card pane, project tabs, search, #project, arrows and znBoard.load work" \
  lune run tests/run -- "$A/page.spec.luau"
check "AC5: the zz-rules board row and the README say what the board does" \
  lune run tests/run -- "$A/docs.spec.luau"
check "AC6: the real tracker's board has every registered project and every issue on one column of its project" \
  lune run tests/run -- "$A/real.spec.luau"
check "AC7: the old navigation, Stats, the CLI and the main checkout's refresh stay (promoted board specs, overridden where they assumed the page opens on Rafts)" \
  lune run tests/run -- tests/acceptance/c0042/cli.spec.luau tests/acceptance/c0042/model.spec.luau \
  tests/acceptance/c0042/page.spec.luau tests/acceptance/c0042/smoke.spec.luau tests/acceptance/c0042/vendor.spec.luau \
  tests/acceptance/c0107/keep.spec.luau tests/acceptance/c0107/label.spec.luau tests/acceptance/c0107/page.spec.luau \
  tests/acceptance/c0107/views.spec.luau tests/acceptance/c0073/board-stats.spec.luau tests/acceptance/c0073/chart.spec.luau \
  tests/acceptance/c0073/history.spec.luau tests/acceptance/c0073/stats.spec.luau tests/acceptance/c0057/open.spec.luau \
  tests/acceptance/c0048/board-docs.spec.luau tests/acceptance/c0048/board-workflow.spec.luau \
  tests/acceptance/c0070/board-refresh.spec.luau tests/acceptance/c0172/narrowed.spec.luau tests/tooling/board.spec.luau
check "AC8: metrics counts review rounds by the board's rule, and the README picture spec (overridden) stays green" \
  lune run tests/run -- "$A/metrics.spec.luau" tests/tooling/metrics-rounds.spec.luau tests/acceptance/c0043/rounds.spec.luau \
  tests/acceptance/c0111/metrics-lessons.spec.luau tests/acceptance/c0116/issue-design.spec.luau \
  tests/acceptance/c0116/retired.spec.luau tests/acceptance/c0115/readme.spec.luau
check "AC9: the eight overridden specs are exactly the reviewed overrides (the prototype's text, pinned by sha, no edit tolerated)" \
  bash -c 'git -C "$1" cat-file -e "$2^{commit}" && git -C "$1" diff --exit-code "$2" -- "${@:3}"' _ "$ZN_ROOT" 6043e33f1ea44d306097d7b745e876de9337e58c \
  z-nile/tests/acceptance/c0042/model.spec.luau z-nile/tests/acceptance/c0042/smoke.spec.luau z-nile/tests/acceptance/c0107/keep.spec.luau z-nile/tests/acceptance/c0107/page.spec.luau z-nile/tests/acceptance/c0107/views.spec.luau z-nile/tests/acceptance/c0115/readme.spec.luau z-nile/tests/acceptance/c0172/narrowed.spec.luau z-nile/tests/tooling/board.spec.luau
check "AC10: real.spec and the board spec declare their inputs (every blob and HEAD)" \
  bash -c 'grep -qxF -e "$(printf "tests/acceptance/c0118/real.spec.luau\t*")" tests/inputs.tsv && grep -qxF -e "$(printf "tests/tooling/board.spec.luau\t*")" tests/inputs.tsv'
finish

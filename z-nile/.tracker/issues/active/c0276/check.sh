#!/usr/bin/env bash
# Acceptance checks for c0276. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0276 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0276"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: board.withVerdicts puts heartbeat and minutes (floored) on a card whose claim is lost, parked, stale (unknown too) or never beaten, none on live or unclaimed ones; changes nothing without a verdict and never its input; puts lost work first inside each bucket and band, longest silent first, the rest as before; and the page draws lost Nm, parked, stale? and no beat on cards, on band heads (a raft's own claim), on list rows of issues and rafts and in both panes." lune run tests/run -- "$A/verdicts.spec.luau"
check "AC2: ./zn board and the board a main-checkout sync rebuilds carry each verdict (an issue's and a raft's own) with lost work first; unreadable pull requests leave stale claims stale, and unreadable heartbeats, an unreachable origin, a vanished document and a malformed beat branch each build the page (a rebuild too), the command succeeding, with exactly one warning on stderr and one note on the page (the model's notes, drawn above every view; absent when nothing failed); a sync's rebuild fetches main no second time, under any spelling of main; a protected checkout, a checkout with PICKMAN_PUBLISH=0 and a checkout with no origin at all read no remote for the board (no fetch of main or of the beat branches) and prints nothing." lune run tests/run -- "$A/board.spec.luau"
check "AC3: the promoted board specs (c0042, c0118, c0070's board-refresh, tooling/board) still pass: the real checkout is protected in the spec runner and reads no remote; fixture repositories are not, and read the verdicts on every rebuild (c0070 holds because its two pages read the same verdicts)." lune run tests/run -- "$PWD"/tests/acceptance/c0042/*.spec.luau "$PWD"/tests/acceptance/c0118/*.spec.luau "$PWD"/tests/acceptance/c0070/board-refresh.spec.luau "$PWD"/tests/tooling/board.spec.luau
check "AC4: the board row of zz-rules and the README's board paragraph name the marks, lost work first, the protected-checkout rule and that only a main-checkout sync (and ./zn board) builds the page." bash -c '
  set -e
  g() { grep -qF -e "$1" "$2" || { echo "missing in $2: $1" >&2; exit 1; }; }
  R="$ZN_ROOT/z-nile"
  row() { grep -F -e "| board |" "$R/skills/zz-rules/SKILL.md" | grep -qF -e "$1" || { echo "the board row of zz-rules lacks: $1" >&2; exit 1; }; }
  for w in "lost 35m" "parked" "stale?" "no beat" "lost work comes first" "unprotected checkout" "rebuild nothing"; do row "$w"; done
  for w in "lost 35m" "no beat" "lost work comes first" "c0276"; do g "$w" "$R/README.md"; done
'

finish

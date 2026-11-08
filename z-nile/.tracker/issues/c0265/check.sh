#!/usr/bin/env bash
# Acceptance checks for c0265. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0265 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0265"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the pure rules: a beat is the ref refs/zn/hb/<claim stamp>/<epoch>; a claim is stale only strictly past 900 s and a never-beaten claim is silent since it landed; a stamp is parked when a pull request names any item holding it; the clock, the takeover rule and the watch loop's stops are decided; a stale claim is lost only when the pull requests were read and none names it, parked when one does, and stays unknown when they could not be read; lost work is ordered first and longest silent first; and a new beat deletes only the older beats of its stamp and long-unclaimed ones" lune run tests/run -- "$A/heartbeat.spec.luau"
check "AC2: a claim, ready, new raft, any ./zn command in a claimed worktree (once an interval has passed, never in the main checkout) and beat each write the beat as a ref outside main (main gets only the claim, no file changes, no branch), beat works from the main checkout, keeps another terminal's fresh beat of a claim it has not fetched, never beats from a protected (fenced) checkout, refuses what nobody claims (done items included), and --watch runs only under ./zn run and ends before its bound" lune run tests/run -- "$A/beat.spec.luau"
check "AC3: lost and status say which claims are lost and list them first, tag parked and unconfirmed ones without calling them lost, a never-beaten claim and an unstarted readied raft are lost, a takeover that meets a restamped claim is refused, fold beats, a beat revives one, unreadable beats or pull requests, malformed beat refs and a malformed beat ref make nothing lost and refuse a takeover, a lost claim (an issue's or a raft's) is taken over with a fresh stamp, and the old claimant's carried move is refused and its worktree stops beating" lune run tests/run -- "$A/lost.spec.luau" "$A/edge.spec.luau"
check "AC4: a model step the dispatcher runs on a claimed item beats for it while the step works (not only before or after)" lune run tests/run -- "$HERE/proofs/dispatch.spec.luau"
check "AC5: a hung remote is bounded and a failed beat attempt is not retried inside the interval, beat --watch says a failed tick and keeps beating and stops when its claim is restamped, and a long check beats while it runs" lune run tests/run -- "$HERE/proofs/race.spec.luau"
check "AC6: the usage text, zz-rules, the skills and the README name the heartbeat: beat and lost commands, the loop under ./zn run --time 3600, and lost work before rank in the README's Order section" bash -c '
  set -e
  g() { grep -qF -e "$1" "$2" || { echo "missing in $2: $1" >&2; exit 1; }; }
  R="$ZN_ROOT/z-nile"
  for c in "  beat <id>" "  lost "; do g "$c" "$R/engine/main.luau"; done
  for w in "refs/zn/hb/" "./zn beat" "./zn lost" "parked"; do g "$w" "$R/skills/zz-rules/SKILL.md"; done
  for s in z-design z-raft z-run zz-execute; do g "./zn beat" "$R/skills/$s/SKILL.md"; g "--time 3600" "$R/skills/$s/SKILL.md"; done
  for s in z-design z-raft z-run; do g "./zn lost" "$R/skills/$s/SKILL.md"; done
  sed -n "/^### Order/,/^### /p" "$R/README.md" | grep -qF "./zn lost" || { echo "README Order does not name ./zn lost" >&2; exit 1; }
  grep -qE "^\| .* \| c0265 \| exists \|" "$R/README.md" || { echo "README roadmap has no c0265 exists row" >&2; exit 1; }
'

finish

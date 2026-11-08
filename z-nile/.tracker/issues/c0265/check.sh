#!/usr/bin/env bash
# Acceptance checks for c0265 (the core layer). SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0265 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0265"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the pure rules: a beat is the branch hb/<claim stamp> whose commit subject carries the epoch, replaced with a lease on the sha seen (create-only when there is none) and never backwards; a rejected beat learns whether it lost the claim; a claim is stale only strictly past 900 s and a never-beaten claim is silent since it landed; a stamp is parked when a pull request names any item holding it; the clock, the tuning settings and the watch loop's stops are decided; a stale claim is lost only when the pull requests were read and none names it, parked when one does, and stays unknown when they could not be read; lost work is ordered first and longest silent first; and only long-unclaimed branches are listed for deletion, each with its lease" lune run tests/run -- "$A/heartbeat.spec.luau"
check "AC2: beat writes the beat as a one-commit branch hb/<stamp> that changes no path (main gets nothing, ./zn busy stays silent) from the main checkout and from a worktree, never backwards, keeps another terminal's fresh beat of a claim it has not fetched and prunes a long-gone one, never beats from a protected (fenced) checkout (it refuses before any network call), refuses what nobody claims (done items included), and --watch refuses to run without a numeric bound; a beat that races a takeover is rejected by its lease and the beater learns it lost the claim, a create-only beat that races one deletes what it created, and a co-beater's lease rejection retries silently" lune run tests/run -- "$A/beat.spec.luau" "$A/edge.spec.luau"
check "AC3: lost and status say which claims are lost and list them first (the longest silent first), tag parked and unconfirmed ones without calling them lost, a never-beaten claim and an unstarted readied raft are lost, a pull request naming only a raft parks it and its members, a questions.md parks, a beat revives a lost claim, unreadable beats or pull requests and a malformed beat branch make nothing lost, and a protected checkout reads no remote (status refuses before any fetch, lost says so)" lune run tests/run -- "$A/lost.spec.luau"
check "AC4: (the proof is pinned by hash, so a changed proof fails here) beat --watch says a failed tick, keeps beating, ends before its bound and stops when its claim is restamped, and a hung remote is bounded: lost gives up after the net limit and says so" bash -c '[[ ! -d "$0/acceptance" ]] || { [[ $(git hash-object "$0/proofs/race.spec.luau") == 829c390536f71a5d196e3d7ad1f5b48acb05a8c0 ]] || { echo "proofs/race.spec.luau changed since it was pinned" >&2; exit 1; }; lune run tests/run -- "$0/proofs/race.spec.luau"; }' "$HERE"
check "AC5: the usage text, zz-rules, the skills and the README name the heartbeat: beat and lost commands, the loop under ./zn run --time 3600, the lost-first pick in z-design, z-raft and z-run, lost work before rank in the README's Order section, the roadmap row, and the NTP sentence in SETUP.md" bash -c '
  set -e
  g() { grep -qF -e "$1" "$2" || { echo "missing in $2: $1" >&2; exit 1; }; }
  R="$ZN_ROOT/z-nile"
  for c in "  beat <id>" "  lost "; do g "$c" "$R/engine/main.luau"; done
  for w in "refs/heads/hb/" "./zn beat" "./zn lost" "parked" "Take lost work first"; do g "$w" "$R/skills/zz-rules/SKILL.md"; done
  for s in z-design z-raft z-run zz-execute; do g "./zn beat" "$R/skills/$s/SKILL.md"; g "--time 3600" "$R/skills/$s/SKILL.md"; done
  for s in z-design z-raft z-run; do g "./zn lost" "$R/skills/$s/SKILL.md"; done
  sed -n "/^### Order/,/^### /p" "$R/README.md" | grep -qF "./zn lost" || { echo "README Order does not name ./zn lost" >&2; exit 1; }
  grep -qF "NTP" "$ZN_ROOT/SETUP.md" || { echo "SETUP.md does not name NTP" >&2; exit 1; }
  grep -qE "^\| .* \| c0265 \| exists \|" "$R/README.md" || { echo "README roadmap has no c0265 exists row" >&2; exit 1; }
'

finish

#!/usr/bin/env bash
# Acceptance checks for c0274. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0274 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0274"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the pure rules: a takeover creates the taker's branch create-only and deletes only the old owner's with a lease on its sha, in one plan; only an explicit lost verdict for the stamp origin still holds allows it (live, stale, parked, never-beaten and unknown do not); the refusal names why (alive with minutes and limit, parked, never beaten, no verdict with its reason); a stamp is held, unheld, taken over or ended; the old owner is told its claim was taken over (naming the stamp now) or ended" lune run tests/run -- "$A/plan.spec.luau"
check "AC2: every claim publish remembers its stamp in the worktree that made it (an issue's, a raft's, new raft's) and the main checkout none; a beat is bound to that stamp: from the claiming worktree it beats, a bare beat from a checkout that holds no claim is refused naming --adopt and writes nothing, an item that is not a claim is refused as such first, --adopt takes a claim on and remembers it in a worktree, never over a remembered different stamp (a restarted --watch loop included), the dispatcher's --adopt --stamp S refuses a restamped item and writes no memory, a main-checkout adoption writes none, the refusals never drop the memory, a worktree that claimed before the memory existed is held through tracker-claim-<id>, and a give-back and a release end it" lune run tests/run -- "$A/memory.spec.luau"
check "AC3: a lost claim (an issue's or a rafting claim with its member following) is taken over by status <id> preparing (a member of a lost rafting claim only through its raft, the taker of a rafting claim becoming its owner), recorded in the claim commit's subject, with a fresh stamp, its old heartbeat branch deleted and the taker's created in one atomic push, and the taker remembers its stamp and its carried move passes; a live, parked, never-beaten or unknown claim is refused with the reason and nothing moves; a claim restamped between the verdict and the publish is refused; a swap that meets an old owner's beat is rejected by its lease, re-read and repeated once, and a refused swap is said without failing the claim; the old claimant's carried prepared and its give-back (an issue's and a raft's), its beat, beat --adopt and beat --watch are refused with <id>'s claim was taken over (now <stamp>) and the taker's branch is untouched; a lost readied raft is taken over by stop (its subject records the lost stamp) then ready, the old lead's done is refused (ended after a stop, taken after the ready) stop records the verdict it read in its subject (live even with the pull requests unreadable, lost with the minutes), no worktree is re-adopted in place after a stop and ready (a plain --adopt and done stay refused, and so does a memory of a stamp the raft never carried), the old rafting owner's member moves (a give-back, a carried prepared) are refused by the raft's memory, a lost recombine is taken over whole, and the old rafting owner's release with or without --force is refused" lune run tests/run -- "$A/takeover.spec.luau"
check "AC4: the usage text, zz-rules, the skills and the README name the takeover: beat <id> [--watch] [--adopt] in the usage line, --adopt, live or parked, (takes over and taken over (now in zz-rules, a lost prep and origin/prep-<slug> in z-design, a lost rafting claim in z-raft, a lost raft and --adopt in z-run, numbered copy and ./zn lost in z-stop, and the roadmap row" bash -c '
  set -e
  g() { grep -qF -e "$1" "$2" || { echo "missing in $2: $1" >&2; exit 1; }; }
  R="$ZN_ROOT/z-nile"
  g "beat <id> [--watch] [--adopt]" "$R/engine/main.luau"
  for w in "(takes over" "taken over (now" "--adopt" "live or parked"; do g "$w" "$R/skills/zz-rules/SKILL.md"; done
  g "lost prep" "$R/skills/z-design/SKILL.md"; g "origin/prep-<slug>" "$R/skills/z-design/SKILL.md"
  g "lost rafting claim" "$R/skills/z-raft/SKILL.md"
  g "lost raft" "$R/skills/z-run/SKILL.md"; g "--adopt" "$R/skills/z-run/SKILL.md"
  g "numbered copy" "$R/skills/z-stop/SKILL.md"; g "./zn lost" "$R/skills/z-stop/SKILL.md"
  grep -qE "^\| .* \| c0274 \| exists \|" "$R/README.md" || { echo "README roadmap has no c0274 exists row" >&2; exit 1; }
'

finish

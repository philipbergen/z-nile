#!/usr/bin/env bash
# Acceptance checks for f0265. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0265 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0265"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the pure rules: a beat is the ref refs/zn/hb/<claim stamp>/<epoch>, a claim is lost only after strictly more than the stale limit, a claim nobody beat is silent since it landed, lost work is ordered first and longest silent first, and a new beat deletes only the older beats of its stamp and of unclaimed stamps" lune run tests/run -- "$A/heartbeat.spec.luau"
check "AC2: a claim, ready and beat each write the beat as a ref outside main (main gets only the claim, no file changes, no branch), beat works from the main checkout, and it refuses what nobody claims" lune run tests/run -- "$A/beat.spec.luau"
check "AC3: lost and status say which claims are lost and list them first, a beat revives one, a claim nobody beat turns lost from its landing, an unreadable origin marks nothing lost, and status refuses a live claim and takes over a lost one" lune run tests/run -- "$A/lost.spec.luau"
check "AC4: a model step the dispatcher runs on a claimed item beats for it while the step works" lune run tests/run -- "$A/dispatch.spec.luau"
check "AC5: the usage text, the skills and the README name the heartbeat, the beat and lost commands and the lost-first pick" bash -c '
  set -e
  g() { grep -qF -e "$1" "$2" || { echo "missing in $2: $1" >&2; exit 1; }; }
  for c in "  beat <id>" "  lost "; do g "$c" "$ZN_ROOT"/z-nile/engine/main.luau; done
  g "refs/zn/hb/" "$ZN_ROOT"/z-nile/skills/zz-rules/SKILL.md
  g "./zn beat" "$ZN_ROOT"/z-nile/skills/zz-rules/SKILL.md
  g "./zn lost" "$ZN_ROOT"/z-nile/skills/zz-rules/SKILL.md
  for s in z-design z-run zz-execute; do g "./zn beat" "$ZN_ROOT/z-nile/skills/$s/SKILL.md"; done
  g "./zn lost" "$ZN_ROOT"/z-nile/skills/z-design/SKILL.md
  g "f0265" "$ZN_ROOT"/z-nile/README.md
  g "lost" "$ZN_ROOT"/z-nile/README.md
'

finish

#!/usr/bin/env bash
# Exit criteria for R0115. SEQUESTERED: never edit during execution.
# Runs the raft's project gate, every member issue's check.sh, then raft-level end-to-end checks.
# ac.sh runs this from the raft's project home (pickman/, z-nile/); $ZN_ROOT is the repository root. The project's gate
# proves that project alone; a game pull request's merger runs `z-nile/check.sh --full`, which covers the others (c0120).
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: project gate passes (affected)" "$ZN_ROOT/z-nile/check.sh" --project z-nile --affected
# every issue naming this raft, including emergent ones
for dir in $("$ZN_ROOT/zn" members R0115); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" "$ZN_ROOT/zn" promote-check R0115

# RC1: the real engine on this branch's tree reads both carried closes (c0278, Design section 8).
closed_in() {
  local project=$1 id=$2
  "$ZN_ROOT/zn" list closed --project "$project" | grep -qw -e "$id" || { echo "list closed --project $project does not name $id"; return 1; }
  if "$ZN_ROOT/zn" list --project "$project" | grep -qw -e "$id"; then echo "list --project $project still offers $id"; return 1; fi
}
check "RC1: the engine lists c0268 and c0224 as closed and no longer offers them" bash -c "$(declare -f closed_in); ZN_ROOT='$ZN_ROOT'; closed_in z-nile c0268 && closed_in arcade c0224"

finish

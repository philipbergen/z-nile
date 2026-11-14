#!/usr/bin/env bash
# Exit criteria for R0099. SEQUESTERED: never edit during execution.
# Runs the raft's project gate, every member issue's check.sh, then raft-level end-to-end checks.
# ac.sh runs this from the raft's project home (pickman/, z-nile/); $ZN_ROOT is the repository root. The project's gate
# proves that project alone; a game pull request's merger runs `z-nile/check.sh --full`, which covers the others (c0120).
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: project gate passes (affected)" "$ZN_ROOT/z-nile/check.sh" --project z-nile --affected
# every issue naming this raft, including emergent ones
for dir in $("$ZN_ROOT/zn" members R0099); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" "$ZN_ROOT/zn" promote-check R0099

check "RC1: the raft's members are exactly c0263 c0280 c0282 c0283 c0284" bash -c 'got=$("$ZN_ROOT/zn" members R0099 | sed "s|.*/||" | sort | tr "\n" " "); [[ $got == "c0263 c0280 c0282 c0283 c0284 " ]] || { echo "members: $got"; exit 1; }'
check "RC2: the engine has one list of agent-session variables, and AGENT_VARS is that table" bash -c '[[ $(grep -c "^provenance.AGENT_MARKERS = {" engine/provenance.luau) == 1 ]] && grep -q "^provenance.AGENT_VARS = provenance.AGENT_MARKERS" engine/provenance.luau && ! grep -q "^provenance.AGENT_VARS = {" engine/provenance.luau'
check "RC3: the engine loads with every layer's commands (the 200-local cap holds) and ./zn who prints a real item's history" bash -c '"$ZN_ROOT/zn" who c0263 | grep -q idea'
check "RC4: the board's item view has the Provenance section and the board builds" bash -c 'grep -q provenanceOf engine/board.html && "$ZN_ROOT/zn" board >/dev/null'

finish

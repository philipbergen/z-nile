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

check "RC1: the five layers are members, and any other member is an emergent issue" bash -c 'm=$("$ZN_ROOT/zn" members R0099); for id in c0263 c0280 c0282 c0283 c0284; do case "$m" in *"/$id"*) ;; *) echo "missing member $id"; exit 1;; esac; done; for dir in $m; do id=$(basename "$dir"); case " c0263 c0280 c0282 c0283 c0284 " in *" $id "*) continue;; esac; grep -q "^emergent: true" "$ZN_ROOT/$dir/$id.md" || { echo "$id is a member and not emergent"; exit 1; }; done'
check "RC2: the engine has one list of agent-session variables, and AGENT_VARS is that table" bash -c '[[ $(grep -c "^provenance.AGENT_MARKERS = {" engine/provenance.luau) == 1 ]] && grep -q "^provenance.AGENT_VARS = provenance.AGENT_MARKERS" engine/provenance.luau && ! grep -q "^provenance.AGENT_VARS = {" engine/provenance.luau'
check "RC3: the engine loads with every layer's commands (the 200-local cap holds) and ./zn who prints a real item's history, within two minutes" bash -c '"$ZN_ROOT/zn" run --time 120 -- "$ZN_ROOT/zn" who c0263 | grep -q idea'
check "RC4: the board builds on the real tree within two minutes and carries a provenance key and the section code" bash -c 'out="$ZN_ROOT/.cache/r0099-rc4"; mkdir -p "$out"; "$ZN_ROOT/zn" run --time 120 -- "$ZN_ROOT/zn" board -O --out "$out/board.html" >/dev/null && grep -q "\"provenance\"" "$out/board.html" && grep -q "provenanceOf(" engine/board.html'
check "RC5: the board build on the real tree reads the history with exactly one git cat-file --batch (c0284 AC3 at real scale)" bash -c 'out="$ZN_ROOT/.cache/r0099-rc5"; mkdir -p "$out"; rm -f "$out/trace"; GIT_TRACE="$out/trace" "$ZN_ROOT/zn" run --time 120 -- "$ZN_ROOT/zn" board -O --out "$out/board.html" >/dev/null && [[ $(grep -c "cat-file --batch" "$out/trace") == 1 ]]'

finish

#!/usr/bin/env bash
# Exit criteria for R0101. SEQUESTERED: never edit during execution.
# Runs the raft's project gate, every member issue's check.sh, then raft-level end-to-end checks.
# ac.sh runs this from the raft's project home (pickman/, z-nile/); $ZN_ROOT is the repository root. The project's gate
# proves that project alone; a game pull request's merger runs `z-nile/check.sh --full`, which covers the others (c0120).
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: project gate passes (affected)" "$ZN_ROOT/z-nile/check.sh" --project pickman --affected
# every issue naming this raft, including emergent ones
for dir in $("$ZN_ROOT/zn" members R0101); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" "$ZN_ROOT/zn" promote-check R0101

# the raft is specs only: the Theme and the rollback rest on it, and no member can check it for the other
check "RC1: the branch changes nothing of the game: no file under src, no Rojo project, no script, not the architecture map" git diff --quiet origin/main...HEAD -- src default.project.json lobby.project.json scripts .tracker/architecture.md

finish

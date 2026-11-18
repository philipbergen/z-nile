#!/usr/bin/env bash
# Exit criteria for R0133. SEQUESTERED: never edit during execution.
# Runs the raft's project gate, every member issue's check.sh, then raft-level end-to-end checks.
# ac.sh runs this from the raft's project home (pickman/, z-nile/); $ZN_ROOT is the repository root. The project's gate
# proves that project alone; a game pull request's merger runs `z-nile/check.sh --full`, which covers the others (c0120).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # before ac.sh changes the directory
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: project gate passes (affected)" "$ZN_ROOT/z-nile/check.sh" --project z-nile --affected
# every issue naming this raft, including emergent ones
for dir in $("$ZN_ROOT/zn" members R0133); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" "$ZN_ROOT/zn" promote-check R0133

# c0374's spec reads every finished check.sh, so each member's own check.sh must pass its rule before done moves it
check "RC1: no member's check.sh names a path c0120's finished rule reports once it is in done/" \
	lune run "$HERE/finished-rule.luau"


finish

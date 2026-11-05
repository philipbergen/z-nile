#!/usr/bin/env bash
# Exit criteria for R0078. SEQUESTERED: never edit during execution.
# Runs the raft's project gate, every member issue's check.sh, then raft-level end-to-end checks.
# ac.sh runs this from the raft's project home (pickman/, z-nile/); $ZN_ROOT is the repository root. The project's gate
# proves that project alone; the merger's `z-nile/check.sh --full` covers the others (c0120).
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: project gate passes (full)" "$ZN_ROOT/z-nile/check.sh" --project z-nile --full
# every issue naming this raft, including emergent ones
for dir in $("$ZN_ROOT/zn" members R0078); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" "$ZN_ROOT/zn" promote-check R0078

check "RC1: the raft changes nothing but its own folder and its two members' folders (no code is written)" bash -c 'cd "$ZN_ROOT" && base=$(git merge-base origin/main HEAD) || { echo "no origin/main to compare with"; exit 1; }
	extra=$(git diff --name-only "$base" | grep -v -E "^z-nile/\.tracker/(rafts|issues)/(active/|done/)?(R0078|c0173|c0174)/") || true
	[[ -z $extra ]] || { printf "files outside the raft and its members:\n%s\n" "$extra"; exit 1; }'

finish

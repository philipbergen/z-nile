#!/usr/bin/env bash
# Exit criteria for R0271. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "RC0: repo gate passes (full)" scripts/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(scripts/tracker.sh members R0271); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" scripts/tracker.sh promote-check R0271

check "RC1: no c0790 acceptance spec names what R0210's gate scan bans, or runs a shell string" bash -c '
  # the banned list is read from the scan itself, so this file names none of it
  f=tests/tooling/repo-fence.spec.luau
  [ -f "$f" ] || { echo "$f is missing: R0210 is not merged"; exit 1; }
  names=$(sed -n "/^local NAMES = {/,/^}/p" "$f" | grep -o "\"[^\"]*\"" | tr -d "\"")
  [ -n "$names" ] || { echo "read no banned names from $f"; exit 1; }
  bad=""
  for d in $(scripts/tracker.sh members R0271); do
    [ -d "$d/acceptance" ] || continue
    while IFS= read -r n; do
      hit=$(grep -rliF -- "$n" "$d/acceptance" || true)
      [ -z "$hit" ] || bad="$bad$hit names $n\n"
    done <<<"$names"
    hit=$(grep -rnE "\"(ba)?sh\", *\{ *\"-c\"|process\.create" "$d/acceptance" || true)
    [ -z "$hit" ] || bad="$bad$hit\n"
  done
  [ -z "$bad" ] || { printf "%b" "$bad"; exit 1; }'

finish

#!/usr/bin/env bash
# Exit criteria for R0005. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: repo gate passes (full)" z-nile/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(./zn members R0005); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" ./zn promote-check R0005

# Every aliased require spec in src, as "file:line:spec" (single or double quotes, optional spaces).
src_alias_requires() {
  grep -rnoE "require\([[:space:]]*[\"'][@][^\"']*" src | sed -E "s/require\([[:space:]]*[\"']//"
}
# RC1: src uses no alias except @self/ and @game/ReplicatedStorage/ (Roblox reads no .luaurc; other
# @game roots don't replicate to clients or load a second module copy: design-review-001 F2).
only_allowed_aliases() {
  local bad
  bad=$(src_alias_requires | grep -vE ":(@self/|@game/ReplicatedStorage/)")
  [ -z "$bad" ] || { echo "$bad"; return 1; }
}
check "RC1: src requires use only relative paths, @self/ or @game/ReplicatedStorage/" only_allowed_aliases

finish

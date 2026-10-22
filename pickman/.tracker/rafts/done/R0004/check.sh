#!/usr/bin/env bash
# Exit criteria for R0004. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: repo gate passes (full)" ../z-nile/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(../zn members R0004); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" ../zn promote-check R0004

# RC1: adapters stay thin (architecture rule 3): decisions live in Logic. Prep prototype: 175 lines.
check "RC1: src/server + src/client hold at most 350 non-blank lines" bash -c '
  n=$(cat $(find src/server src/client -name "*.luau") | grep -cv "^[[:space:]]*$")
  echo "$n non-blank adapter lines"; [ "$n" -le 350 ]'
# Every aliased require spec in src, as "file:line:spec" (single or double quotes, optional spaces).
src_alias_requires() {
  grep -rnoE "require\([[:space:]]*[\"'][@][^\"']*" src | sed -E "s/require\([[:space:]]*[\"']//"
}
# src uses no alias except @self/ and @game/ReplicatedStorage/ (Roblox reads no .luaurc; other
# @game roots don't replicate to clients or load a second module copy: design-review-001 F2).
only_allowed_aliases() {
  local bad
  bad=$(src_alias_requires | grep -vE ":(@self/|@game/ReplicatedStorage/)")
  [ -z "$bad" ] || { echo "$bad"; return 1; }
}
# RC2: adapters reach Logic only through @game/ReplicatedStorage/... (c0041), and use Session (server)
# and View (client) that way. Logic never names @game (the meta rule bans the word "game" in Logic).
adapters_use_game_alias() {
  only_allowed_aliases || return 1
  local rel
  rel=$(grep -rnE "require\([[:space:]]*[\"'](\.\./)+shared" src/server src/client)
  [ -z "$rel" ] || { echo "$rel"; return 1; }
  grep -rqF "@game/ReplicatedStorage/Shared/Logic/Session" src/server || { echo "server does not use Session via @game"; return 1; }
  grep -rqF "@game/ReplicatedStorage/Shared/Logic/View" src/client || { echo "client does not use View via @game"; return 1; }
}
check "RC2: adapters require Logic via @game/ReplicatedStorage/Shared/Logic only" adapters_use_game_alias

finish

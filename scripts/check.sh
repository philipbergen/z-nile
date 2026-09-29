#!/usr/bin/env bash
# The repo gate. See .claude/skills/testing/SKILL.md.
#   scripts/check.sh               # same as --affected
#   scripts/check.sh --affected [--base REF]
#   scripts/check.sh --full
# Exits non-zero on the first failing stage.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.rokit/bin:$PATH"

mode=affected
base_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) mode=full ;;
    --affected) mode=affected ;;
    --base) base_args=(--base "$2"); shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

stage() { printf '\n== %s\n' "$1"; }
LUAU_DIRS=(src tests scripts tracker)

stage "format (stylua --check)"
stylua --check "${LUAU_DIRS[@]}"

stage "lint (selene)"
selene --quiet "${LUAU_DIRS[@]}"

stage "types (luau-lsp analyze, src with Roblox definitions)"
mkdir -p .cache
defs=.cache/globalTypes.d.luau
if [[ ! -s $defs ]]; then
  curl -fsSL -o "$defs" \
    https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.None.d.luau
fi
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --definitions="$defs" --sourcemap=sourcemap.json --base-luaurc=.luaurc \
  --ignore='**/_Index/**' src

stage "types (luau-lsp analyze, tests + scripts with Lune definitions)"
lune_version=$(lune --version | awk '{print $2}')
[[ -d "$HOME/.lune/.typedefs/$lune_version" ]] || lune setup >/dev/null
# tracker/**/acceptance specs are not type-checked here: they target code that may not exist yet.
# They are checked once `tracker.sh done` promotes them into tests/acceptance/.
luau-lsp analyze --base-luaurc=.luaurc --platform=standard tests scripts

stage "build (rojo)"
rojo build default.project.json -o .cache/check.rbxl >/dev/null
echo "ok"

stage "tests ($mode)"
if [[ $mode == full ]]; then
  lune run tests/run
else
  selection=$(lune run scripts/affected -- "${base_args[@]}")
  if [[ -z $selection ]]; then
    echo "no specs affected"
  elif [[ $selection == ALL ]]; then
    echo "infrastructure changed: running all specs"
    lune run tests/run
  else
    echo "$selection"
    # shellcheck disable=SC2086
    lune run tests/run -- $selection
  fi
fi

printf '\nGATE PASSED (%s)\n' "$mode"

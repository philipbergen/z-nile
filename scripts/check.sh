#!/usr/bin/env bash
# The repo gate. See .claude/skills/testing/SKILL.md.
#   scripts/check.sh               # same as --affected
#   scripts/check.sh --affected [--base REF]
#   scripts/check.sh --full
# Static stages run concurrently (scripts/lib/par.sh); any failure fails the gate before the tests.
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

source scripts/lib/par.sh
gate_start=$(par_now)

stage() { printf '\n== %s\n' "$1"; }
LUAU_DIRS=(src tests scripts tracker)

# prerequisites the static stages read: serial and fast
mkdir -p .cache
defs=.cache/globalTypes.d.luau
# Files at the top of .cache are written outside the checkout and renamed into place: a spec could have swapped a
# symlink in there, and a rename replaces it instead of writing through it (R0210 review 006 F1).
if [[ ! -s $defs || -L $defs ]]; then
  t=$(mktemp)
  curl -fsSL -o "$t" \
    https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.None.d.luau && mv -f "$t" "$defs"
fi
build_place() { # $1 the file under .cache, then the build command. rojo writes through a symlink at its output path,
  # so it builds outside and the result is renamed in
  local out=$1 d
  shift
  d=$(mktemp -d) && "$@" -o "$d/$out" && mv -f "$d/$out" ".cache/$out"
}
rojo sourcemap default.project.json -o sourcemap.json
lune_version=$(lune --version | awk '{print $2}')
[[ -d "$HOME/.lune/.typedefs/$lune_version" ]] || lune setup >/dev/null

# the six static stages run concurrently; each is reported (timed) whether or not it passes
# tracker/**/acceptance specs are not type-checked here: they target code that may not exist yet.
# They are checked once `tracker.sh done` promotes them into tests/acceptance/.
par_start "format (stylua --check)" stylua --check "${LUAU_DIRS[@]}"
par_start "lint (selene)" selene --quiet "${LUAU_DIRS[@]}"
par_start "types (luau-lsp analyze, src with Roblox definitions)" \
  luau-lsp analyze --definitions="$defs" --sourcemap=sourcemap.json --base-luaurc=.luaurc \
  --ignore='**/_Index/**' src
par_start "types (luau-lsp analyze, tests + scripts with Lune definitions)" \
  luau-lsp analyze --base-luaurc=.luaurc --platform=standard tests scripts
par_start "build (rojo)" build_place check.rbxl rojo build default.project.json
par_start "build lobby (rojo)" build_place check-lobby.rbxl rojo build lobby.project.json
par_wait || exit 1

stage "tests ($mode)"
if [[ $mode == full ]]; then
  lune run tests/run
else
  selection=$(lune run scripts/affected -- ${base_args[@]+"${base_args[@]}"})
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

printf '\ngate wall time: %ss\n' "$(par_elapsed "$gate_start" "$(par_now)")"
printf '\nGATE PASSED (%s)\n' "$mode"

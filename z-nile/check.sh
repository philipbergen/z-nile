#!/usr/bin/env bash
# The repo gate (c0114: z-nile's, covering every project). See .claude/skills/testing/SKILL.md.
#   z-nile/check.sh               # same as --affected
#   z-nile/check.sh --affected [--base REF]
#   z-nile/check.sh --full
# Static stages run concurrently (z-nile/lib/par.sh); any failure fails the gate before the tests.
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

source z-nile/lib/par.sh
gate_start=$(par_now)

stage() { printf '\n== %s\n' "$1"; }
# The format and lint folders: src, tests, scripts, z-nile and every project root of z-nile/projects.toml
# (z-nile/roots, design review 001 F5). stylua skips hidden folders unless named, so each root is named itself (selene
# and luau-lsp read them anyway). Read inside the stages, so a registry that does not parse fails them, not the setup.
luau_stage() { # $1: stylua or selene, then its arguments
  local dirs
  dirs=$(lune run z-nile/roots -- --luau-dirs) || { echo "check.sh: z-nile/projects.toml does not parse" >&2; return 1; }
  # shellcheck disable=SC2086
  "$@" $dirs
}

# prerequisites the static stages read: serial and fast
mkdir -p .cache
# A spec may have swapped a symlink in at the top of .cache (the jail can't refuse a swap, c0077 E1): unlink every
# one, never following it, before anything here writes there. Writes under .cache then go through replace-file.pl,
# which renames a fresh file into place, so a link swapped in later is replaced instead of written through.
find .cache -mindepth 1 -maxdepth 1 -type l -exec rm -f {} +
defs=.cache/globalTypes.d.luau
if [[ ! -s $defs || -L $defs ]]; then
  t=$(mktemp "${TMPDIR:-/tmp}/globalTypes.XXXXXX")
  curl -fsSL -o "$t" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.None.d.luau ||
    { rm -f "$t"; echo "check.sh: could not download the Luau global types (globalTypes.d.luau)" >&2; exit 1; }
  perl z-nile/lib/replace-file.pl "$defs" "$t" || { rm -f "$t"; exit 1; }
  rm -f "$t"
fi
build_place() { # $1 the output file's name, then the build command. rojo writes through a symlink at its output path,
  # so it builds in a fresh folder outside and the result is renamed in (replace-file.pl); the folder always goes
  local out=$1 d rc
  shift
  d=$(mktemp -d "${TMPDIR:-/tmp}/check-build.XXXXXX") || return 1
  "$@" -o "$d/$out" && perl z-nile/lib/replace-file.pl ".cache/$out" "$d/$out"
  rc=$?
  rm -rf "$d"
  return $rc
}
rojo sourcemap default.project.json -o sourcemap.json
lune_version=$(lune --version | awk '{print $2}')
[[ -d "$HOME/.lune/.typedefs/$lune_version" ]] || lune setup >/dev/null

# the six static stages run concurrently; each is reported (timed) whether or not it passes
# tracker/**/acceptance and z-nile/.tracker/**/acceptance specs are not type-checked here: they target code that may
# not exist yet. They are checked once `./zn done` promotes them into tests/acceptance/.
par_start "format (stylua --check)" luau_stage stylua --check
par_start "lint (selene)" luau_stage selene --quiet
par_start "types (luau-lsp analyze, src with Roblox definitions)" \
  luau-lsp analyze --definitions="$defs" --sourcemap=sourcemap.json --base-luaurc=.luaurc \
  --ignore='**/_Index/**' src
par_start "types (luau-lsp analyze, tests + scripts + z-nile with Lune definitions)" \
  luau-lsp analyze --base-luaurc=.luaurc --platform=standard --ignore='**/.tracker/**' tests scripts z-nile
par_start "build (rojo)" build_place check.rbxl rojo build default.project.json
par_start "build lobby (rojo)" build_place check-lobby.rbxl rojo build lobby.project.json
par_wait || exit 1

stage "tests ($mode)"
if [[ $mode == full ]]; then
  lune run tests/run
else
  selection=$(lune run z-nile/affected -- ${base_args[@]+"${base_args[@]}"})
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

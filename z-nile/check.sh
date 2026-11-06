#!/usr/bin/env bash
# The repo gate (c0114: z-nile's), one per project (c0120). See z-nile/skills/zz-test/SKILL.md.
#   z-nile/check.sh [--project <name>]... [--affected [--base REF] [--fresh] | --full]
#   z-nile/check.sh [--project <name>]... --plan   # print what each stage reads, run nothing, write nothing
# With no --project it runs every project of z-nile/projects.toml (`./zn done`, `./zn land`); each --project adds
# one (pickman/check.sh is `--project pickman`). A project's specs run from its home, which z-nile/roots gives
# (`--projects`): z-nile/ for z-nile, pickman/ for pickman (the root belongs to no project).
# Static stages run concurrently (z-nile/lib/par.sh); any failure fails the gate before the tests.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.rokit/bin:$PATH"

mode=affected
plan=
fresh=
base_args=()
wanted=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) mode=full ;;
    --plan) plan=1 ;;
    --affected) mode=affected ;;
    --fresh) fresh=1 ;;
    --base) base_args=(--base "$2"); shift ;;
    --project) wanted+=("$2"); shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done
if [[ -n $fresh && $mode == full ]]; then
  echo "check.sh: unknown or conflicting flags: --fresh is an affected flag, not for --full" >&2
  exit 2
fi

# The projects: name, home and root, one per line, from the registry's reader for the shell (z-nile/roots, c0114). A
# tree without it predates c0114: its one project lives at the root, with its places there.
if [[ -f z-nile/roots.luau ]]; then
  registry=$(lune run z-nile/roots -- --projects) ||
    { echo "check.sh: z-nile/projects.toml does not parse (lune run z-nile/roots)" >&2; exit 1; }
else
  registry=$'pickman\t.\ttracker'
fi
names=() homes=() roots=()
while IFS=$'\t' read -r n h r; do
  [[ -n $n ]] || continue
  names+=("$n") homes+=("$h") roots+=("$r")
done < <(printf '%s\n' "$registry") # not a here-string: bash writes one to a temp file, which a jail may refuse
if [[ ${#wanted[@]} -gt 0 ]]; then
  for w in "${wanted[@]}"; do
    found=
    for n in "${names[@]}"; do [[ $n == "$w" ]] && found=1; done
    [[ -n $found ]] || { echo "check.sh: no project $w in z-nile/projects.toml" >&2; exit 2; }
  done
fi
picked() { # picked <name>: is the project in this run?
  [[ ${#wanted[@]} -eq 0 ]] && return 0
  local w
  for w in "${wanted[@]}"; do [[ $w == "$1" ]] && return 0; done
  return 1
}

[[ -n $plan ]] || ./zn reap --auto || true
source z-nile/lib/par.sh
gate_start=$(par_now)

stage() { printf '\n== %s\n' "$1"; }
prefix() { [[ $1 == . ]] && echo "" || echo "$1/"; }

# What each picked project's stages read, by its home (prefix p: "" at the root, "pickman/" for pickman):
#   format and lint: a game's p/src p/tests p/scripts, the tooling's whole home (z-nile/) with the root's scripts/
#                    (c0114's shims, no project's), and the project's root (z-nile/roots --luau-dirs; stylua skips
#                    hidden folders, so each .tracker/ is named itself)
#   Roblox types:    p/src, with p/sourcemap.json from p/default.project.json
#   Lune types:      a game's p/tests p/scripts, the tooling's whole home and the root's scripts/; never a .tracker/
#   builds:          every p/*.project.json, into p/.cache/check.rbxl (default) or p/.cache/check-<stem>.rbxl
LUAU_DIRS=()
LUNE_DIRS=()
places=() # "<home>|<project file>"
srcs=()   # "<home>"
for i in "${!names[@]}"; do
  picked "${names[$i]}" || continue
  h=${homes[$i]} p=$(prefix "${homes[$i]}")
  if [[ $h == . || -d ${p}src ]]; then
    for d in "${p}tests" "${p}scripts"; do [[ -d $d ]] && LUNE_DIRS+=("$d"); done
  else
    LUNE_DIRS+=("$h")
  fi
  if [[ $h == . && -d ${names[$i]} ]]; then LUNE_DIRS+=("${names[$i]}"); fi
  if [[ ${names[$i]} == z-nile && -d scripts ]]; then LUNE_DIRS+=(scripts); fi
  [[ -d ${p}src ]] && srcs+=("$h")
  for f in "${p}"*.project.json; do [[ -f $f ]] && places+=("$h|$f"); done
done

if [[ -f z-nile/roots.luau ]]; then
  # shellcheck disable=SC2207
  LUAU_DIRS=($(lune run z-nile/roots -- --luau-dirs ${wanted[@]+"${wanted[@]}"})) || exit 1
else
  for d in src tests scripts tracker; do [[ -d $d ]] && LUAU_DIRS+=("$d"); done
fi

source z-nile/lib/fence.sh
# The root's .cache and every home's get the fence's refusals before anything here writes there (the builds write
# each home's check*.rbxl), and before --plan (they only read): a symlinked or bad .cache, which an unjailed spec could
# leave, refuses (code review 004 F3, 005 F3). The set is fence.sh's (pickman_fence_all, code review 005 F2).
pickman_fence_all "$(pwd -P)" refusals || exit 1
if [[ -n $plan ]]; then
  printf 'format: %s\n' "${LUAU_DIRS[*]-}"
  printf 'lint: %s\n' "${LUAU_DIRS[*]-}"
  for h in ${srcs[@]+"${srcs[@]}"}; do printf 'types (Roblox): %ssrc, from %s\n' "$(prefix "$h")" "$h"; done
  printf 'types (Lune): %s\n' "${LUNE_DIRS[*]-}"
  for e in ${places[@]+"${places[@]}"}; do printf 'build: %s\n' "${e#*|}"; done
  [[ -d z-nile/skills ]] && printf 'skills: %s\n' .claude/skills
  for i in "${!names[@]}"; do
    picked "${names[$i]}" || continue
    [[ -d $(prefix "${homes[$i]}")tests ]] && printf 'specs: %s, from %s\n' "${names[$i]}" "${homes[$i]}"
  done
  exit 0
fi

# prerequisites the static stages read: serial and fast
for i in "${!names[@]}"; do
  picked "${names[$i]}" || continue
  c="$(prefix "${homes[$i]}").cache"
  mkdir -p "$c"
  # A spec may have swapped a symlink in at the top of .cache (the jail can't refuse a swap, c0077 E1): unlink every
  # one, never following it, before anything here writes there. Writes under .cache then go through replace-file.pl,
  # which renames a fresh file into place, so a link swapped in later is replaced instead of written through.
  find "$c" -mindepth 1 -maxdepth 1 -type l -exec rm -f {} +
done
# the root's .cache is no project's home (c0120) but holds the board and the gate's downloads; it and every home's
# get the fence's sentinel, so git finds no repository there (design review 005 F2)
mkdir -p .cache
find .cache -mindepth 1 -maxdepth 1 -type l -exec rm -f {} +
pickman_fence_all "$(pwd -P)" strict || exit 1
defs=.cache/globalTypes.d.luau
if [[ ! -s $defs || -L $defs ]]; then
  t=$(mktemp "${TMPDIR:-/tmp}/globalTypes.XXXXXX")
  curl -fsSL -o "$t" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.None.d.luau ||
    { rm -f "$t"; echo "check.sh: could not download the Luau global types (globalTypes.d.luau)" >&2; exit 1; }
  perl z-nile/lib/replace-file.pl "$defs" "$t" || { rm -f "$t"; exit 1; }
  rm -f "$t"
fi

# c0165: an affected gate that already passed on this exact content is reused whole, its static report included. The
# digest holds the projects, the base, each project's selection, the tools and every file (z-nile/specs); a failed read gives none and the gate runs.
digest=
report=
if [[ $mode == affected ]]; then
  export PICKMAN_GATE_PID=$$
  pnames=()
  for i in "${!names[@]}"; do picked "${names[$i]}" && pnames+=("${names[$i]}"); done
  proj_csv=$(IFS=,; echo "${pnames[*]}")
  trap 'for i in "${!homes[@]}"; do rm -f "$(prefix "${homes[$i]}").cache/spec-norecord-$$"; done; [[ -z $report ]] || rm -f "$report"' EXIT
  digest=$(lune run z-nile/specs -- digest --mode affected --projects "$proj_csv" ${base_args[@]+"${base_args[@]}"} 2>/dev/null) || digest=
  if [[ -n $digest && -z $fresh ]]; then
    if reused=$(lune run z-nile/specs -- gate-check --digest "$digest" 2>/dev/null) &&
      [[ $reused == *"reused: an affected gate passed on this content"* ]]; then
      printf '%s\n' "$reused"
      printf '\nGATE PASSED (affected)\n'
      exit 0
    fi
  fi
fi

build_place() { # $1 the output file, then the build command. rojo writes through a symlink at its output path,
  # so it builds in a fresh folder outside and the result is renamed in (replace-file.pl); the folder always goes
  local out=$1 d rc
  shift
  d=$(mktemp -d "${TMPDIR:-/tmp}/check-build.XXXXXX") || return 1
  "$@" -o "$d/$(basename "$out")" && perl z-nile/lib/replace-file.pl "$out" "$d/$(basename "$out")"
  rc=$?
  rm -rf "$d"
  return $rc
}
# a sourcemap's paths are relative to its project file, so a home's src types are read from that home
for h in ${srcs[@]+"${srcs[@]}"}; do
  (cd "$h" && rojo sourcemap default.project.json -o sourcemap.json)
done
roblox_types() { # roblox_types <home>: src with the Roblox definitions, from the home
  local h=$1 up
  up=$(cd "$h" && pwd -P)
  up=${up#"$(pwd -P)"}
  up=${up//[^\/]/}
  up=${up//\//../}
  (cd "$h" && luau-lsp analyze --definitions="${up}$defs" --sourcemap=sourcemap.json --base-luaurc="${up}.luaurc" \
    --ignore='**/_Index/**' src)
}
lune_version=$(lune --version | awk '{print $2}')
[[ -d "$HOME/.lune/.typedefs/$lune_version" ]] || lune setup >/dev/null

# the static stages run concurrently; each is reported (timed) whether or not it passes
# .tracker/**/acceptance specs are not type-checked here: they target code that may not exist yet. They are checked
# once `./zn done` promotes them into their project's tests/acceptance/.
if [[ ${#LUAU_DIRS[@]} -gt 0 ]]; then
  par_start "format (stylua --check)" stylua --check "${LUAU_DIRS[@]}"
  par_start "lint (selene)" selene --quiet "${LUAU_DIRS[@]}"
fi
for h in ${srcs[@]+"${srcs[@]}"}; do
  par_start "types (luau-lsp analyze, $(prefix "$h")src with Roblox definitions)" roblox_types "$h"
done
if [[ ${#LUNE_DIRS[@]} -gt 0 ]]; then
  par_start "types (luau-lsp analyze, ${LUNE_DIRS[*]} with Lune definitions)" \
    luau-lsp analyze --base-luaurc=.luaurc --platform=standard --ignore='**/.tracker/**' --ignore='**/.cache/**' "${LUNE_DIRS[@]}"
fi
for e in ${places[@]+"${places[@]}"}; do
  h=${e%%|*} f=${e#*|}
  stem=$(basename "$f" .project.json)
  out="$(prefix "$h").cache/check.rbxl"
  [[ $stem == default ]] || out="$(prefix "$h").cache/check-$stem.rbxl"
  par_start "build (rojo $f)" build_place "$out" rojo build "$f"
done
# the skill links (c0115): one committed relative link in .claude/skills per skill folder, every project's
[[ -d z-nile/skills ]] && par_start "skills (./zn skills --check)" ./zn skills --check
report=$(mktemp "${TMPDIR:-/tmp}/gate-report.XXXXXX")
par_wait >"$report" || { cat "$report"; exit 1; }
cat "$report"
[[ $mode == affected ]] || rm -f "$report"

# The specs: each project's from its home (its runner, its .cache, its lock), so one project's never see another's.
run_specs() { # run_specs <home> [spec paths relative to the home]
  local h=$1
  shift
  if [[ $h == . ]]; then
    lune run tests/run -- "$@"
  else
    (cd "$h" && lune run tests/run -- "$@")
  fi
}
for i in "${!names[@]}"; do
  picked "${names[$i]}" || continue
  n=${names[$i]} h=${homes[$i]}
  [[ -d $(prefix "$h")tests ]] || { stage "tests ($mode): $n has no tests/"; continue; }
  stage "tests ($mode): $n"
  if [[ $mode == full ]]; then
    run_specs "$h"
  else
    selection=$(lune run z-nile/affected -- --project "$n" ${base_args[@]+"${base_args[@]}"})
    if [[ -z $selection ]]; then
      echo "no specs affected"
    elif [[ $selection == ALL ]]; then
      echo "infrastructure changed: running all specs"
      lune run z-nile/specs -- run --project "$n" ${fresh:+--fresh} --all
    else
      echo "$selection"
      # shellcheck disable=SC2086
      lune run z-nile/specs -- run --project "$n" ${fresh:+--fresh} -- $selection
    fi
  fi
done

# the gate passed: record it, unless the tree moved while it ran (a spec that wrote a file) or a run was not recorded
if [[ -n $digest ]]; then
  digest_after=$(lune run z-nile/specs -- digest --mode affected --projects "$proj_csv" ${base_args[@]+"${base_args[@]}"} 2>/dev/null) || digest_after=
  if [[ $digest_after == "$digest" ]]; then
    lune run z-nile/specs -- gate-record --digest "$digest" --mode affected --projects "$proj_csv" --summary "$report" || true
  fi
fi

printf '\ngate wall time: %ss\n' "$(par_elapsed "$gate_start" "$(par_now)")"
printf '\nGATE PASSED (%s)\n' "$mode"

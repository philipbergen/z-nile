#!/usr/bin/env bash
# Helpers for tracker check.sh files (acceptance criteria as executable checks).
#   source z-nile/lib/ac.sh   # cds to the check.sh's project home (c0120): pickman/ for pickman's, z-nile/ for z-nile's
#   check "AC1: description" <command> [args...]
#   finish
# Each check prints PASS/FAIL; finish exits non-zero if any failed.
# With AC_LIST set (non-empty), check only prints LIST <label> and runs nothing; finish says "listed".
# The check.sh that sourced this (the script bash runs), as a physical path, before any cd.
_ac_physical() { echo "$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)/$(basename "$1")"; }
_ac_script=$(_ac_physical "$0")
# A check.sh is run with bash, never sourced (c0120 review 001 F6): sourced, $0 is the caller, so the home below would
# be the caller's and a pathspec guard could pass on a folder that isn't there. The file that sourced this (past the
# scripts/lib/ac.sh forwarder), when it is a check.sh, must be the script bash runs. (An inline
# `bash -c 'source <ac.sh>; check …'` sources no check.sh, and keeps working.)
_ac_outer=
for _ac_f in "${BASH_SOURCE[@]:1}"; do
  [[ ${_ac_f##*/} == ac.sh ]] && continue
  _ac_outer=$(_ac_physical "$_ac_f")
  break
done
if [[ ${_ac_outer##*/} == check.sh && $_ac_outer != "$_ac_script" ]]; then
  echo "ac.sh: $_ac_outer is sourced by $_ac_script: run a check.sh with bash, never source it" >&2
  exit 1
fi
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
# Guard git for everything this check.sh runs (zz-test skill, "Specs never touch the real repository"). The guards
# missing fails closed (c0114): a check.sh never runs unfenced.
if [[ ! -f z-nile/lib/fence.sh ]]; then
  echo "ac.sh: $(pwd -P)/z-nile/lib/fence.sh is missing: refusing to run checks without the repository guards" >&2
  exit 1
fi
source z-nile/lib/fence.sh || exit 1
# The root's .cache and every project home's (c0120 code review 005 F2: pickman_fence_all owns the set, from the
# registry): a check.sh's fixtures go in its home's .cache, and git must find no repository in any of them. Inside a
# jailed spec run that starts a check.sh, the jail refuses the sentinels outside its own .cache, which
# pickman_home_fence waives by the jail's markers alone; anywhere else a refusal refuses.
pickman_fence_all "$(pwd -P)" check || exit 1
# The repository root, for checks that name the engine or the gate from a project's home ("$ZN_ROOT/zn").
ZN_ROOT="$(pwd -P)"
export ZN_ROOT
# Run from the check.sh's project home (c0120): the folder z-nile/projects.toml gives the project whose root holds
# it, so the paths a sequestered check.sh names (src/..., tests/..., git pathspecs) resolve where it was written for.
# z-nile/roots reads the registry for the shell (c0114). A check.sh under a .tracker/ folder whose project can't be
# read fails closed: run from the wrong folder, a guard like `git diff --quiet -- src/server` passes vacuously.
# The fence above covers the root and every home (c0120 review 001 F1, code review 005 F2), because the
# check.sh's own fixtures go in the home's .cache: git must find no repository there or below it. In fence.sh's
# steps (review 002 F1): its .cache joins the ceiling (cannot fail, always); a .cache that isn't a plain folder, or
# a sentinel that is a folder, refuses (reads only, every mode); the environment's guards are set whole; then the
# sentinel is written. Only that last write may fail without refusing, and only inside the runner's jail: fence.sh's
# pickman_home_fence decides, by the jail's markers, never by the failure.
_ac_rel=${_ac_script#"$ZN_ROOT/"}
_ac_home=
if _ac_projects=$(lune run z-nile/roots -- --projects); then
  # process substitution, not a here-string: bash writes a here-string to a temp file, which a jail may refuse
  while IFS=$'\t' read -r _ac_name _ac_h _ac_root; do
    if [[ -n $_ac_root && $_ac_rel == "$_ac_root/"* ]]; then
      _ac_home=$_ac_h
      break
    fi
  done < <(printf '%s\n' "$_ac_projects")
fi
if [[ -z $_ac_home ]]; then
  if [[ $_ac_rel == .tracker/* || $_ac_rel == */.tracker/* ]]; then
    echo "ac.sh: $_ac_rel is under no project root that z-nile/roots lists: refusing to guess its home" >&2
    exit 1
  fi
  _ac_home=.
fi
cd "$_ac_home" || exit 1
export PATH="$HOME/.rokit/bin:$PATH"
_ac_failed=0
_ac_total=0

check() {
  local label="$1"; shift
  _ac_total=$((_ac_total + 1))
  if [[ -n ${AC_LIST:-} ]]; then
    printf 'LIST  %s\n' "$label"
    return 0
  fi
  local out
  if out=$("$@" 2>&1); then
    printf 'PASS  %s\n' "$label"
  else
    _ac_failed=$((_ac_failed + 1))
    printf 'FAIL  %s\n' "$label"
    printf '%s\n' "$out" | tail -n 25 | sed 's/^/      /'
  fi
}

finish() {
  if [[ $_ac_total -eq 0 ]]; then
    echo "FAIL  no acceptance checks defined (an empty check.sh never passes)"
    return 1
  fi
  if [[ -n ${AC_LIST:-} ]]; then
    printf -- '---- %d criteria listed (none run)\n' "$_ac_total"
    return 0
  fi
  printf -- '---- %d/%d criteria passed\n' "$((_ac_total - _ac_failed))" "$_ac_total"
  [[ $_ac_failed -eq 0 ]]
}

#!/usr/bin/env bash
# Tracker CLI entry point. See .claude/skills/tracker/SKILL.md.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.rokit/bin:$PATH"
# `launch` is handled here, not in Lune: the command must be exec'd so it gets the terminal, signals and
# exit status natively (Lune can't forward stdin to a child, and dies on Ctrl-C while the child lives on).
if [[ ${1:-} == launch ]]; then
  shift
  target=${1:-}
  if [[ -z $target || $target == -- ]]; then echo "usage: tracker.sh launch <R-id|name> [-- <command> [args...]]" >&2; exit 1; fi
  shift
  if [[ ${1:-} == -- ]]; then shift
  elif [[ $# -gt 0 ]]; then echo "launch: unexpected argument '$1' (put the command after --)" >&2; exit 1; fi
  cmd=claude
  if [[ $# -gt 0 ]]; then cmd=$1; shift; fi
  # check the command first, so a typo doesn't leave a worktree behind; a relative path would mean the repo
  # root before the cd and the worktree after it
  if [[ -z $cmd || ( $cmd == */* && $cmd != /* ) ]]; then
    echo "cannot run '$cmd': give a command on PATH or an absolute path" >&2; exit 1; fi
  cmdpath=$(type -P "$cmd" 2>/dev/null) || cmdpath=
  if [[ -z $cmdpath || ! -x $cmdpath ]]; then echo "cannot run $cmd: not found" >&2; exit 1; fi
  path=$(lune run scripts/tracker/main -- worktree "$target") || exit 1
  # cd "" succeeds on bash 3.2, and a failed cd inside && does not stop set -e: check the path ourselves
  if [[ $path != /* || $path == *$'\n'* || ! -d $path ]]; then
    echo "launch: no usable worktree path for $target" >&2; exit 1; fi
  echo "launching $cmd in $path" >&2
  cd "$path" || exit 1
  exec "$cmd" "$@"
fi
exec lune run scripts/tracker/main -- "$@"

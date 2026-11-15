#!/usr/bin/env bash
# c0359: run specs in the prototype clone (experiments/clone.sh made it), from its z-nile/ home, with the dispatched
# step's environment dropped. Usage, from the worktree's top:
#   ./zn run --time 3600 -- bash z-nile/.tracker/issues/c0359/experiments/specs.sh <clone> <spec path relative to z-nile/>...
set -uo pipefail
clone=$1
shift
case "$clone" in "${TMPDIR:-/tmp}"*) ;; *) echo "not a clone under \$TMPDIR: $clone" >&2; exit 2 ;; esac
for v in $(compgen -e | grep '^ZN_' || true); do unset "$v"; done
unset GH_CONFIG_DIR GH_TOKEN GITHUB_TOKEN
PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '/z-nile/bin$' | paste -sd: -)
export PATH
cd "$clone/z-nile" || exit 2
lune run tests/run -- "$@"

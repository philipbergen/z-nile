#!/usr/bin/env bash
# c0359: a throwaway clone of this worktree's HEAD for the prototype, outside every checkout, with no origin and the
# dispatched step's environment dropped (lesson z-design/clone-experiments-drop-the-step-environment). Prints its path.
# It sets no git identity: the spec runner refuses a repository whose identity is a fixture's, and nothing here commits.
# Usage (from the worktree's top): ./zn run --time 120 -- bash z-nile/.tracker/issues/c0359/experiments/clone.sh
# then: git -C <clone> apply z-nile/.tracker/issues/c0359/experiments/prototype.patch, and copy this item's folder in
set -euo pipefail
for v in $(compgen -e | grep '^ZN_' || true); do unset "$v"; done
unset GH_CONFIG_DIR GH_TOKEN GITHUB_TOKEN
PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '/z-nile/bin$' | paste -sd: -)
src=$(pwd -P)
base=$(mktemp -d "${TMPDIR:-/tmp}/c0359-proto.XXXXXX")
case "$base" in "$src"/*) echo "the clone would sit inside this checkout" >&2; exit 1 ;; esac
git clone -q --no-hardlinks "$src" "$base/repo"
git -C "$base/repo" remote remove origin
git -C "$base/repo" checkout -q -B main
echo "$base/repo"

#!/usr/bin/env bash
# E3 (c0292 prep): the existing work the lesson meets. (a) every project root's .tracker on this tree (= origin/main
# plus this prep) through the gate's two stages; (b) each open prep-* or raft-* branch on origin: the issue and raft
# folders it changes against its merge base with origin/main, at its head, through the same stages. Read-only on the
# repository (git archive into its own mktemp -d, removed on exit). Run from the repository root:
#   ./zn run --time 300 -- bash z-nile/.tracker/issues/c0292/experiments/E3-existing-work.sh
set -uo pipefail
export PATH="$HOME/.rokit/bin:$PATH"
tmp=$(mktemp -d) && trap 'rm -rf "$tmp"' EXIT
roots=$(lune run z-nile/roots -- --luau-dirs | tr ' ' '\n' | grep '\.tracker$' | sort -u)
for r in $roots; do
  stylua --check "$r" >/dev/null 2>&1; f=$?; selene --quiet "$r" >/dev/null 2>&1; l=$?
  echo "a) $r: stylua $f selene $l"
done
for b in $(git for-each-ref --format='%(refname:short)' 'refs/remotes/origin/prep-*' 'refs/remotes/origin/raft-*'); do
  base=$(git merge-base origin/main "$b") || continue
  dirs=$(git diff --name-only "$base" "$b" -- '*/.tracker/issues/*' '*/.tracker/rafts/*' |
    sed -E 's#^(.*/\.tracker/(issues|rafts)/(active/|done/|retired/)?[^/]+)/.*#\1#' | sort -u)
  [[ -n $dirs ]] || continue
  t="$tmp/${b//\//_}" && mkdir -p "$t"
  # shellcheck disable=SC2086
  git archive "$b" stylua.toml selene.toml $dirs 2>/dev/null | tar -x -C "$t" 2>/dev/null
  n=$(find "$t" -name '*.luau' | wc -l | tr -d ' ')
  # shellcheck disable=SC2086
  (cd "$t" && stylua --check $dirs >/dev/null 2>&1); f=$?
  # shellcheck disable=SC2086
  (cd "$t" && selene --quiet $dirs >/dev/null 2>&1); l=$?
  echo "b) $b ($n .luau in $(echo $dirs | wc -w | tr -d ' ') folders): stylua $f selene $l"
done

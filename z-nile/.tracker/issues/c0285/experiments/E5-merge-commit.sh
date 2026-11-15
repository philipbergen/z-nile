#!/bin/bash
# E5 (c0285): for three capture shapes, land a PR (capture commit C, then a prep commit E that edits the captured
# document) two ways in a throwaway repository under .cache, and print what the capture lookup takes:
#   squash: one commit with C's subject but E's tree;  merge: a --no-ff merge commit, C reaches main whole.
# Run from the checkout's top: ./zn run --time 120 -- z-nile/.tracker/issues/c0285/experiments/E5-merge-commit.sh
set -euo pipefail
top=$(pwd -P); here="$top/z-nile/.tracker/issues/c0285/experiments"
base="$top/.cache/c0285-e5"; rm -rf "$base"; mkdir -p "$base"
doc() { printf -- '---\nid: %s\n---\n# %s\n\n## Problem\n%s\n\n## Solution\n%s\n' "$1" "$1" "$2" "$3"; }
for shape in edit add rename; do
  for how in squash merge; do
    r="$base/$shape-$how"; mkdir -p "$r"; cd "$r"
    git init -q -b main; git config user.name e5; git config user.email e5@example.invalid
    mkdir -p z/.tracker/issues; echo x > other.txt
    case $shape in
      edit) mkdir -p z/.tracker/issues/c0001; doc c0001 "stub" "" > z/.tracker/issues/c0001/c0001.md; old=c0001 ;;
      add) old= ;;
      rename) mkdir -p z/.tracker/issues/f0001; doc f0001 "stub" "" > z/.tracker/issues/f0001/f0001.md; old=f0001 ;;
    esac
    git add -A; git commit -q -m "tracker: new ${old:-none} stub"
    git checkout -q -b capture
    [[ $shape == rename ]] && git mv -k z/.tracker/issues/f0001 z/.tracker/issues/c0001 && git mv z/.tracker/issues/c0001/f0001.md z/.tracker/issues/c0001/c0001.md
    mkdir -p z/.tracker/issues/c0001; doc c0001 "the captured problem" "CAPTURED solution" > z/.tracker/issues/c0001/c0001.md
    git add -A; git commit -q -m "tracker: new c0001 The title"
    doc c0001 "the captured problem" "CAPTURED solution, plus PREP detail" > z/.tracker/issues/c0001/c0001.md
    git commit -qam "tracker: prep c0001 The title"
    git checkout -q main; echo y >> other.txt; git commit -qam "main moves"
    if [[ $how == squash ]]; then
      git merge -q --squash capture > /dev/null; git commit -q -m "tracker: new c0001 The title (#2)"
    else
      git merge -q --no-ff capture -m "tracker: prep c0001 The title (#2)"
    fi
    echo "== $shape, $how"
    lune run "$here/E5-capture.luau"
  done
done

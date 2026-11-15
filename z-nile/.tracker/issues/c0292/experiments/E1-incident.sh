#!/usr/bin/env bash
# E1 (c0292 prep): the gate's format and lint stages over c0261's issue folder, before and after its fix commit.
# Reads git objects only; writes only under its own mktemp -d, removed on exit. Run from the repository root:
#   ./zn run --time 120 -- bash z-nile/.tracker/issues/c0292/experiments/E1-incident.sh
set -uo pipefail
export PATH="$HOME/.rokit/bin:$PATH"
tmp=$(mktemp -d) && trap 'rm -rf "$tmp"' EXIT
dir=z-nile/.tracker/issues/c0261
for c in 95119f89 59b76a99; do # the prep head the merge gate failed on (PR #259); its fix "formatted and linted for the gate"
  t="$tmp/$c" && mkdir -p "$t"
  git archive "$c" stylua.toml selene.toml "$dir" | tar -x -C "$t" || { echo "E1: cannot read $c"; exit 2; }
  echo "== $c: $(find "$t/$dir" -name '*.luau' | wc -l | tr -d ' ') .luau files in $dir"
  (cd "$t" && stylua --check "$dir" > "$tmp/$c.fmt" 2>&1); f=$?
  (cd "$t" && selene --quiet "$dir" > "$tmp/$c.lint" 2>&1); l=$?
  echo "stylua --check exit $f ($(grep -c '^Diff in' "$tmp/$c.fmt") files differ)"
  echo "selene exit $l: $(grep -cE '^[^ ].*(error|warning)\[' "$tmp/$c.lint") problems"
  grep -oE '(error|warning)\[[a-z_]+\]' "$tmp/$c.lint" | sort | uniq -c
  eval "r_$c=\"$f $l\""
done
# pass: the failing head fails both stages, the fix passes both (what the merge gate read)
[[ $r_95119f89 == "1 1" && $r_59b76a99 == "0 0" ]] && echo "E1 PASS" || { echo "E1 FAIL: $r_95119f89 / $r_59b76a99"; exit 1; }

#!/usr/bin/env bash
# E2: the step-1 bullet merges cleanly with every open branch that edits z-design's SKILL.md, in either order.
# Reads git objects only; writes in a fresh mktemp -d, which it removes.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd -P)"
top="$(git -C "$here" rev-parse --show-toplevel)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
F=z-nile/skills/z-design/SKILL.md
git -C "$top" show origin/main:$F > "$t/base"
# ours: the bullet inserted after step 1's last bullet ("If an issue is missing")
awk -v b="$here/ref-skill-bullet.txt" '{print} /^- If an issue is missing, create it first with the `z-ticket` skill\.$/{while((getline l < b)>0) print l}' "$t/base" > "$t/ours"
[[ $(grep -c '^- \*\*One prep per issue\*\*' "$t/ours") == 1 ]] || { echo "bullet not inserted"; exit 1; }
for br in $*; do # ./zn run may pass the branches as one word
  git -C "$top" show "origin/$br:$F" > "$t/theirs" 2>/dev/null || { echo "$br: no $F"; continue; }
  if cmp -s "$t/base" "$t/theirs"; then echo "$br: unchanged"; continue; fi
  cp "$t/ours" "$t/a"; if git merge-file -q "$t/a" "$t/base" "$t/theirs"; then r1=clean; else r1=CONFLICT; fi
  cp "$t/theirs" "$t/b"; if git merge-file -q "$t/b" "$t/base" "$t/ours"; then r2=clean; else r2=CONFLICT; fi
  n=$(grep -c '^- \*\*One prep per issue\*\*' "$t/a" || true)
  echo "$br: ours-first $r1, theirs-first $r2, bullet kept $n"
done

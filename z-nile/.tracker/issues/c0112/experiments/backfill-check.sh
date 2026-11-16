#!/usr/bin/env bash
# c0112: check one worker's batch folder against a copy of the tree. Read-only on <repo>; writes only a mktemp copy.
#   backfill-check.sh <repo> <out>
# <out>/harvest/<item>.md is a complete new harvest.md for <item>; <out>/lessons/<skill>--<slug>.md is a lesson draft.
# Prints every problem and ends with "ok", or exits 1. Needs rsync, lune and a ./zn that has c0136's --unattributed.
set -uo pipefail
repo=${1:?usage: backfill-check.sh <repo> <out>}
out=${2:?usage: backfill-check.sh <repo> <out>}
[[ -d $repo/z-nile/engine ]] || { echo "backfill-check: $repo is not a checkout"; exit 2; }
[[ -d $out ]] || { echo "backfill-check: no folder $out"; exit 2; }
repo=$(cd "$repo" && pwd -P)
fail=0
say() { echo "$*"; fail=1; }

pristine=$(mktemp -d) && scratch=$(mktemp -d) || exit 2
trap 'rm -rf "$pristine" "$scratch"' EXIT
for d in "$pristine" "$scratch"; do
  rsync -a --exclude .git --exclude .cache --exclude .worktree "$repo/" "$d/" || exit 2
done

items=()
shopt -s nullglob
# <out>/items.txt (the lead writes it before the launch): the batch's item ids, one per line. A harvest file for an item
# not listed (a held item, another worker's) is refused, and so is a listed item with none.
if [[ -f $out/items.txt ]]; then
  while read -r want; do
    [[ -n $want ]] || continue
    [[ -f $out/harvest/$want.md ]] || say "items.txt lists $want: no harvest/$want.md"
  done <"$out/items.txt"
  for f in "$out"/harvest/*.md; do
    grep -qx "$(basename "$f" .md)" "$out/items.txt" || say "harvest/$(basename "$f"): not an item of this batch (items.txt)"
  done
else
  say "no $out/items.txt: the lead lists the batch's items there before the launch"
fi
for f in "$out"/harvest/*.md; do
  item=$(basename "$f" .md)
  dir=$(cd "$scratch" && ./zn find "$item" 2>/dev/null) || { say "harvest/$item.md: no such item"; continue; }
  cp "$f" "$scratch/$dir/harvest.md"
  items+=("$item")
done
for f in "$out"/lessons/*.md; do
  base=$(basename "$f" .md)
  skill=${base%%--*} slug=${base#*--}
  [[ $base == *--* ]] || { say "lessons/$base.md: name it <skill>--<slug>.md"; continue; }
  folder=
  for c in "$scratch/z-nile/skills/$skill" "$scratch/pickman/skills/$skill"; do [[ -d $c ]] && folder=$c; done
  [[ -n $folder ]] || { say "lessons/$base.md: no skill $skill"; continue; }
  [[ -e $folder/lessons/$slug.md ]] && { say "lessons/$base.md: $skill/$slug already exists"; continue; }
  mkdir -p "$folder/lessons" && cp "$f" "$folder/lessons/$slug.md"
done
((${#items[@]})) || say "no harvest files in $out/harvest"

# <out>/when-change.txt: `<lesson id> <design|build|both>` per line, applied to the scratch copy before the checks (the
# lead applies the same file in the merge pass)
if [[ -f $out/when-change.txt ]]; then
  while read -r lid value; do
    [[ -n $lid ]] || continue
    case $value in design | build | both) ;; *) say "when-change.txt: $lid: the value is design, build or both"; continue ;; esac
    file=
    for c in "$scratch/z-nile/skills/${lid%%/*}/lessons/${lid#*/}.md" "$scratch/pickman/skills/${lid%%/*}/lessons/${lid#*/}.md"; do [[ -f $c ]] && file=$c; done
    [[ -n $file ]] || { say "when-change.txt: no lesson $lid"; continue; }
    perl -0pi -e "s/^when: .*\$/when: $value/m" "$file"
    echo "applied when-change: $lid -> $value"
  done <"$out/when-change.txt"
fi

chk=$(cd "$scratch" && ./zn lessons --check 2>&1) || say "$chk"
# c0181's gate (`--check --policy`: a state key on every lesson, similar lessons merged or marked distinct) when the
# engine has it; a lesson draft is written to its format then (the brief's section "If c0181 has landed")
if grep -q -- '--policy' "$scratch/z-nile/engine/main.luau"; then
  pol=$(cd "$scratch" && ./zn lessons --check --policy 2>&1) || say "policy: $pol"
fi
if ((${#items[@]})); then
  un=$(cd "$scratch" && ./zn lessons --uncovered "${items[@]}" 2>&1) || say "uncovered: $un"
  na=$(cd "$scratch" && ./zn lessons --unattributed "${items[@]}" 2>&1) || say "unattributed: $na"
fi

# No source is lost: the very check AC3 runs at done (acceptance/sources-kept.luau, sequestered), pristine copy against
# the overlaid one. A third lesson moved to a note headed for its finding passes; a dropped one does not.
export PATH="$HOME/.rokit/bin:$PATH"
kept="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/acceptance/sources-kept.luau"
[[ -f $kept ]] || { echo "backfill-check: no $kept"; exit 2; }
res=$(cd "$scratch" && lune run "$kept" -- "$pristine" "$scratch" 2>&1) || say "$res"

if ((fail)); then
  echo "backfill-check: problems above"
  exit 1
fi
echo "ok"

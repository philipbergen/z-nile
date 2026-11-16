#!/bin/bash
# The mutation check of c0252's Rules table, bounded: run as
#   <repo>/zn run --time 3300 -- bash mutrun.sh <name> <rows-file> <results-file>
# <rows-file> has one `<mutant id> <spec path relative to z-nile/>` per line. Each mutant is applied (mutate.py) to a
# throwaway detached worktree of the prototype's tip (.worktree/<name>), the spec runs under `./zn run --time 900`, the
# worktree is reset (`git checkout -- .`) between runs and removed at the end. A run that ends in the runner's tripwire
# because another session's ref appeared is run once more.
name="$1"; rows="$2"; results="$3"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${MUT_OUT:-$HERE/out}"
mkdir -p "$OUT"
REPO="${MUT_REPO:?the prototype worktree (.worktree/proto-c0252)}"
MW="$(dirname "$REPO")/$name"
ZN="$(git -C "$REPO" rev-parse --show-toplevel)/zn"
HASH=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" worktree add --detach "$MW" "$HASH" >/dev/null 2>&1 || { echo "worktree add failed" > "$results"; exit 1; }
echo "base $HASH" > "$results"
while read -r id spec; do
  [ -z "$id" ] && continue
  git -C "$MW" checkout -q -- . && git -C "$MW" clean -fdq -e .cache
  ( cd "$MW" && "$ZN" run --time 60 -- python3 -I "$HERE/mutate.py" "$id" ) > "$OUT/m-$id.apply" 2>&1
  if ! grep -q applied "$OUT/m-$id.apply"; then echo "$id NOT-APPLIED $(cat "$OUT/m-$id.apply")" >> "$results"; continue; fi
  for attempt in 1 2; do
    ( cd "$MW/z-nile" && "$ZN" run --time 900 -- lune run tests/run -- "$spec" ) > "$OUT/m-$id.out" 2>&1
    grep -q "REPOSITORY CHANGED" "$OUT/m-$id.out" || break
  done
  first=$(grep -A1 "^FAIL" "$OUT/m-$id.out" | head -2 | tr '\n' ' ' | cut -c1-360)
  summary=$(grep -E "^[0-9]+ passed" "$OUT/m-$id.out" | tail -1)
  echo "$id | $spec | $summary | $first" >> "$results"
done < "$rows"
git -C "$MW" checkout -q -- .
git -C "$REPO" worktree remove --force "$MW"
echo FINISHED >> "$results"

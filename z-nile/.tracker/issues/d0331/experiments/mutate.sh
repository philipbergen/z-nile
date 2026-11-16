#!/usr/bin/env bash
# d0331 mutation check: each mutant of experiments/mutants.py on the prototype, against the spec files its row
# names. A mutant is killed when the run fails on an assertion (a FAIL line), not on a load or syntax error.
# Usage: ./zn run --time 3500 -- mutate.sh <worktree>
set -uo pipefail
src="$1"; here="$(cd "$(dirname "$0")" && pwd -P)"
killed=0; total=0
while read -r name specs; do
  total=$((total + 1))
  out="$(MUTANT="$name" "$here/proto-run.sh" "$src" $specs 2>&1)"
  if grep -q "could not load spec\|syntax error\|anchor found" <<<"$out"; then echo "BROKEN $name"; echo "$out" | tail -5
  elif grep -q "^FAIL .* :: " <<<"$out"; then killed=$((killed + 1)); echo "killed $name: $(grep -m1 '^FAIL .* :: ' <<<"$out" | sed 's/.*:: //' | cut -c1-90)"
  else echo "SURVIVED $name"; fi
done < <(python3 "$here/mutants.py" --list)
echo "$killed/$total killed"
[[ $killed == "$total" ]]

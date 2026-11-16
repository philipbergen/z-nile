#!/usr/bin/env bash
# Exit criteria for R0117. SEQUESTERED: never edit during execution.
# Runs the raft's project gate, every member issue's check.sh, then raft-level end-to-end checks.
# ac.sh runs this from the raft's project home (pickman/, z-nile/); $ZN_ROOT is the repository root. The project's gate
# proves that project alone; a game pull request's merger runs `z-nile/check.sh --full`, which covers the others (c0120).
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: project gate passes (affected)" "$ZN_ROOT/z-nile/check.sh" --project portal --affected
# every issue naming this raft, including emergent ones
for dir in $("$ZN_ROOT/zn" members R0117); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" "$ZN_ROOT/zn" promote-check R0117

check "RC1: the architecture map composes the three layers: the folded deps comment, Play -> Card once, every other line an edge, every edge main has kept, and the Features headings of f0205, f0208 and f0206 once each, in that order" bash -c '
  doc=.tracker/architecture.md
  block() { awk "BEGIN{p=0} index(\$0, \"\`\`\`deps\")==1 {p=1; next} p && index(\$0, \"\`\`\`\")==1 {exit} p {print}"; }
  deps=$(block < "$doc")
  comments=$(printf "%s\n" "$deps" | grep "^#")
  [ "$comments" = "# Carousel and Card are leaves; so are Pairing and Arena" ] || { printf "deps comment lines are:\n%s\n" "$comments"; exit 1; }
  [ "$(printf "%s\n" "$deps" | grep -c -x -F "Play -> Card")" = 1 ] || { echo "Play -> Card is not there exactly once"; exit 1; }
  odd=$(printf "%s\n" "$deps" | grep -v "^#" | grep -v "^[[:space:]]*$" | grep -v -E "^[A-Za-z][A-Za-z0-9]* -> [A-Za-z][A-Za-z0-9]*$")
  [ -z "$odd" ] || { printf "not an edge:\n%s\n" "$odd"; exit 1; }
  edges() { grep -E "^[A-Za-z][A-Za-z0-9]* -> [A-Za-z][A-Za-z0-9]*$" | sort -u; }
  mainmap=$(git show "origin/main:./$doc") || { echo "cannot read origin/main map"; exit 1; }
  main=$(printf "%s\n" "$mainmap" | block | edges)
  here=$(printf "%s\n" "$deps" | edges)
  lost=$(comm -23 <(printf "%s\n" "$main") <(printf "%s\n" "$here") | grep .)
  [ -z "$lost" ] || { printf "edges main has that this map lost:\n%s\n" "$lost"; exit 1; }
  heads=$(awk "BEGIN{p=0} index(\$0, \"## Features\")==1 {p=1; next} p && index(\$0, \"## \")==1 {exit} p && index(\$0, \"### \")==1 {print}" "$doc")
  prev=0
  for h in "### Carousel and Card (f0205)" "### Play buttons (f0208)" "### Board (f0206)"; do
    at=$(printf "%s\n" "$heads" | grep -n -x -F "$h")
    [ "$(printf "%s\n" "$at" | grep -c .)" = 1 ] || { printf "Features headings are:\n%s\n" "$heads"; exit 1; }
    [ "${at%%:*}" -gt "$prev" ] || { echo "the Features headings are out of order"; exit 1; }
    prev=${at%%:*}
  done
'

finish

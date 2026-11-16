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

check "RC1: the architecture map composes both layers: f0205's then f0208's Features heading, and a deps block of exactly the folded comment and Play -> Card" bash -c '
  doc=.tracker/architecture.md
  deps=$(awk "BEGIN{p=0} index(\$0, \"\`\`\`deps\")==1 {p=1; next} p && index(\$0, \"\`\`\`\")==1 {exit} p {print}" "$doc")
  want=$(printf "%s\n" "# Carousel and Card are leaves; so are Pairing and Arena" "Play -> Card")
  [ "$deps" = "$want" ] || { printf "deps block is:\n%s\n" "$deps"; exit 1; }
  feat=$(awk "BEGIN{p=0} index(\$0, \"## Features\")==1 {p=1; next} p && index(\$0, \"## \")==1 {exit} p && index(\$0, \"### \")==1 {print}" "$doc")
  want=$(printf "%s\n" "### Carousel and Card (f0205)" "### Play buttons (f0208)")
  [ "$feat" = "$want" ] || { printf "Features headings are:\n%s\n" "$feat"; exit 1; }
'

check "RC2: Enter, KeypadEnter and A on the front card send the request its PLAY sends, through the real client boot (f0205's captured \"Enter or A plays\", true through f0208)" bash -c '
  dir=$("$ZN_ROOT/zn" find R0117) || exit 1
  lune run tests/run -- "$dir/checks/play-keys.spec.luau"
'

finish

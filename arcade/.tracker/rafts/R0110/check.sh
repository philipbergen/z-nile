#!/usr/bin/env bash
# Exit criteria for R0110. SEQUESTERED: never edit during execution.
# Runs the raft's project gate, every member issue's check.sh, then raft-level end-to-end checks.
# ac.sh runs this from the raft's project home (pickman/, z-nile/); $ZN_ROOT is the repository root. The project's gate
# proves that project alone; a game pull request's merger runs `z-nile/check.sh --full`, which covers the others (c0120).
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: project gate passes (affected)" "$ZN_ROOT/z-nile/check.sh" --project arcade --affected
# every issue naming this raft, including emergent ones
for dir in $("$ZN_ROOT/zn" members R0110); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" "$ZN_ROOT/zn" promote-check R0110

check "RC1: architecture.md lists both leaves and the deps block is the one comment" bash -c '
  doc=.tracker/architecture.md
  deps=$(awk "BEGIN{p=0} index(\$0, \"\`\`\`deps\")==1 {p=1; next} p && index(\$0, \"\`\`\`\")==1 {exit} p {print}" "$doc")
  printf "%s\n" "$deps" | grep -F -x -q "# PaidPlay and Travel are leaves" || exit 1
  n=$(printf "%s\n" "$deps" | grep -c ".")
  [ "$n" = 1 ] || exit 1
  feat=$(awk "BEGIN{p=0} index(\$0, \"## Features\")==1 {p=1; next} p && index(\$0, \"## \")==1 {exit} p {print}" "$doc")
  printf "%s\n" "$feat" | grep -F -q "### Travel and Places (f0199)" || exit 1
  printf "%s\n" "$feat" | grep -F -q "### PaidPlay and Receipts (f0201)" || exit 1
  grep -F -q "installed by **every place**" "$doc" || exit 1
  exit 0
'

finish

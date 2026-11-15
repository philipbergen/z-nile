#!/usr/bin/env bash
# Acceptance checks for c0271. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
# The lesson is text that c0181 may rewrite, so AC1 reads its words here, once before `./zn done`, and no promoted
# spec pins them (the same choice as c0192's AC1). AC3's spec pins the zz-rules line and zz-execute's exception, and is
# promoted. Each runs from z-nile/ (the item's project home).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0271 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0271"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the lesson zz-rules/read-pr-state-before-pushing reaches design and build, keeps the captured question (gh pr view state, head and the newest comments before this push or report, and the report quotes the state), names PR #256, the three states, what this work's closed PR gets, the earlier use of a name, a failed read and a PR you merged yourself, points at Landing step 2, and its body is at most 1,200 bytes" \
  bash -c 'L=skills/zz-rules/lessons/read-pr-state-before-pushing.md
    [ -f "$L" ] || { echo "no $L"; exit 1; }
    grep -qx "when: both" "$L" || { echo "$L is not when: both"; exit 1; }
    grep -q "^tags: .*github" "$L" && grep -q "^tags: .*landing" "$L" || { echo "$L lacks the tags github and landing"; exit 1; }
    grep -q "^check: .*state, head and newest comments (\`gh pr view <n> --json state,headRefOid,comments\`.*push.*report.*quote the state I read?\$" "$L" || { echo "$L lost the captured check question"; exit 1; }
    b=$(( $(sed -e "1,/^---\$/d" "$L" | wc -c) )); [ "$b" -le 1200 ] || { echo "$L has a body of $b bytes, at most 1200 (c0181 cap for a partly enforced lesson)"; exit 1; }
    body=$(sed -e "1,/^---\$/d" "$L")
    for w in "PR #256" "closed by another session" "\`OPEN\`" "\`CLOSED\`" "\`MERGED\`" "takes nothing" "newest comment" "and stop" "earlier use of the name" "start fresh" "fails twice" "merged yourself" "quotes the state it read" "Landing a change, step 2"; do
      case "$body" in *"$w"*) ;; *) echo "the lesson body does not say: $w"; exit 1;; esac
    done'
check "AC2: the lesson and c0271's harvest note pass ./zn lessons --check and --uncovered, c0271 is on the lesson's sources line, and it is listed for design and for build" \
  bash -c 'Z="$ZN_ROOT/zn"; "$Z" lessons --check && "$Z" lessons --uncovered c0271 || exit 1
    for w in design build; do "$Z" lessons --when $w --full | grep "^== .*skills/zz-rules/lessons/read-pr-state-before-pushing.md" > /dev/null || { echo "not listed for --when $w"; exit 1; }; done
    "$Z" lessons --skill zz-rules --full read-pr-state-before-pushing | grep -E "^sources:.*c0271" > /dev/null || { echo "c0271 is not on the sources line"; exit 1; }'
check "AC3: zz-rules Landing a change step 2 holds the read-the-PR-first bullet word for word as a line of its own, zz-execute Phase 4 says its state read is not carried past, and the lesson the rule names exists" \
  lune run tests/run -- "$A/docs.spec.luau"

finish

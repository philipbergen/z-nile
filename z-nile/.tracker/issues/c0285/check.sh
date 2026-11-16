#!/usr/bin/env bash
# Acceptance checks for c0285. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
# The lesson is text, and c0181 may cut or merge a lesson, so AC1, AC2 and AC4 read it here and no promoted spec pins
# its words (c0192's choice; AC5 likewise for z-ticket's lesson); AC3's spec pins only zz-rules, and is promoted. Each runs from z-nile/.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0285 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0285"
L=skills/zz-rules/lessons/squash-keeps-the-capture-commit.md

# the captured check question, word for word (./zn capture c0285)
Q="Does the squash subject of a capture PR start with 'tracker: new' and list every id its capture commit listed?"

ac1() {
  [[ -f $L ]] || { echo "no $L"; return 1; }
  local n b
  n=$(($(wc -l < "$L"))); [[ $n -le 12 ]] || { echo "$L has $n lines, at most 12"; return 1; }
  b=$(($(awk '/^---$/ { c++; next } c >= 2' "$L" | wc -c))); [[ $b -le 1200 ]] || { echo "$L has a body of $b bytes, at most 1200"; return 1; }
  grep -qx "when: both" "$L" || { echo "$L is not when: both"; return 1; }
  local tags; tags=$(grep "^tags: \[.*\]$" "$L" | sed -e 's/^tags: \[//' -e 's/\]$//' | tr -d ' ' | tr ',' '\n')
  for tag in squash capture merging; do
    printf '%s\n' "$tags" | grep -qx "$tag" || { echo "$L lacks the tag $tag"; return 1; }
  done
  grep -qF "title: A squash that lands a capture keeps its capture commit" "$L" || { echo "$L has another title"; return 1; }
  local c; c=$(grep "^check: " "$L") || { echo "$L has no check"; return 1; }
  [[ $c == "check: $Q"* && $c == *"?" ]] || { echo "$L lost the captured check question: $c"; return 1; }
  [[ $c == *"no later commit of that PR change those documents"*"a merge commit)?" ]] ||
    { echo "$L check does not ask about later edits and the merge commit: $c"; return 1; }
}

ac2() {
  local w
  for w in "PR #258" "2e282833" "#57" "#178" "#265" "#317" "5 of the 26" "./zn capture" "one-line stubs" "first add" \
    "./zn land" "(zz-rules, Merging)" 'gh pr merge --squash' \
    '--subject "tracker: new <every id they list> <title> (#<pr>)"' "(a spend commit changes none)" \
    "a squash shows the later text: land the PR with \`gh pr merge --merge\`" \
    "\`./zn capture <id>\` names the capture commit, with no marker"; do
    grep -qF -- "$w" "$L" || { echo "the lesson does not say: $w"; return 1; }
  done
}

ac4() {
  local Z="$ZN_ROOT/zn" w
  "$Z" lessons --check && "$Z" lessons --uncovered c0285 || return 1
  # read each listing whole before matching: grep -q on a pipe closes it early and lessons dies of a broken pipe
  local out
  for w in design build; do
    out=$("$Z" lessons --when $w --full) || return 1
    grep -qx "== z-nile/$L" <<< "$out" || { echo "not listed for --when $w"; return 1; }
  done
  out=$("$Z" lessons --skill zz-rules --full squash-keeps-the-capture-commit) || return 1
  grep -Eq "^sources:.*c0285" <<< "$out" || { echo "c0285 is not on the sources line (the harvest note)"; return 1; }
  # c0181 first: once lessons know a state, the executor has stopped and asked the user which one this lesson takes
  # (Design, Decisions 6); any state line passes here, and its reason is the user's call, not this check's
  if grep -q not_codifiable "$ZN_ROOT/z-nile/engine/lessons.luau"; then
    grep -Eq "^(enforced_by|not_codifiable):" "$L" || { echo "c0181 has landed: the lesson carries no state (ask the user)"; return 1; }
  fi
}

check "AC1: the lesson zz-rules/squash-keeps-the-capture-commit is short (12 lines, a body of at most 1,200 bytes), reaches design and build, is tagged squash, capture and merging, and keeps the captured check question word for word with the later-edit and merge-commit clause" ac1
check "AC2: the lesson carries the incident (PR #258, 2e282833, the fallbacks, the four other PRs, 5 of 26) and how to apply it (the subject with every id, a merge commit when a later commit edits the capture, ./zn capture after)" ac2
check "AC3: zz-rules Merging keeps a capture's subject at the squash with every id, defines its documents, lands a PR that edits them later by a merge commit, and says a dispatched step must carry no capture commit; Landing a change step 3 points there" lune run tests/run -- "$A/merging-docs.spec.luau"
ac5() {
  local I=skills/z-ticket/lessons/land-a-challenged-idea.md w
  for w in "**Note (c0285's prep, 2026-11-15):**" "merged by zz-rules Merging, which keeps it (lesson zz-rules/squash-keeps-the-capture-commit)" \
    "titled \`tracker: new <id> <title>\`" "#317 was squashed as" "\`./zn capture c0304\` still answers the stub"; do
    grep -qF -- "$w" "$I" || { echo "$I does not say: $w"; return 1; }
  done
}

check "AC4: the lesson and its harvest note pass ./zn lessons --check and --uncovered, it is listed for design and for build, c0285 is on its sources line, and once c0181 has landed it carries a state" ac4
check "AC5: z-ticket's land-a-challenged-idea lesson says its pull request carries the capture commit, is merged by zz-rules Merging and titled tracker: new, with #317 as the case" ac5

finish

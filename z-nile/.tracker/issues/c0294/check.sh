#!/usr/bin/env bash
# Acceptance checks for c0294. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
# The lesson is text, and c0181 may cut or merge a lesson, so every criterion reads it here and no promoted spec pins
# its words (c0192's choice); this issue changes no skill text, so it has no acceptance spec. Each runs from z-nile/.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0294 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0294"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
LESSON="$ZN_ROOT/z-nile/skills/z-ticket/lessons/moved-part-rewrites-the-owner.md"
ID=z-ticket/moved-part-rewrites-the-owner

# the captured check question, word for word (./zn capture c0294), its first letter capitalised
Q="For each answer that moves a part or adds an edge, does the other ticket name the new owner, and can each of its outcomes still be built?"

# the lesson's frontmatter value of `key` (the first line `key: …` between the two `---` lines)
front() { awk -v k="$1: " 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{exit} f&&index($0,k)==1{print substr($0,length(k)+1);exit}' "$LESSON"; }
# the lesson's body: everything after the frontmatter's closing `---`
body() { awk 'c==2{print} $0=="---"{c++}' "$LESSON"; }
# fails naming each of the given fixed strings that the text on stdin lacks
has_all() {
  local text miss=0
  text=$(cat)
  for n in "$@"; do
    if ! grep -qF -- "$n" <<<"$text"; then echo "missing: $n" >&2; miss=1; fi
  done
  return $miss
}

ac1() {
  [[ -f $LESSON ]] || { echo "no lesson at $LESSON" >&2; return 1; }
  local n b
  # a distinct_from: line (c0181's answer to an overlap pair, Decisions 5) is not counted
  n=$(($(grep -vc '^distinct_from: ' "$LESSON")))
  ((n <= 12)) || { echo "the lesson has $n lines (distinct_from: aside), at most 12" >&2; return 1; }
  [[ $(front title) == "An answer that moves a part rewrites the ticket that had it" ]] ||
    { echo "title: is '$(front title)'" >&2; return 1; }
  [[ $(front when) == both ]] || { echo "when: is '$(front when)', not both" >&2; return 1; }
  local tags
  tags=$(front tags | sed -e 's/^\[//' -e 's/\]$//' | tr -d ' ' | tr ',' '\n')
  for t in capture dependencies scope; do
    grep -qx -- "$t" <<<"$tags" || { echo "the lesson lacks the tag $t" >&2; return 1; }
  done
  local c
  c=$(front check)
  [[ $c == "$Q"* ]] || { echo "the check lost the captured question: $c" >&2; return 1; }
  [[ $c == *"And is each ticket this capture cannot edit named to the user?" ]] ||
    { echo "the check does not end with the clause on tickets the capture cannot edit: $c" >&2; return 1; }
  # exactly one sentence is added (Decisions 3)
  [[ $c == "$Q And is each ticket this capture cannot edit named to the user?" ]] ||
    { echo "the check adds more than the one clause: $c" >&2; return 1; }
  b=$(body | wc -c | tr -d ' ')
  # 1,200: short, under c0181's cap for a partly enforced lesson and well under its 2,500 for one no check enforces
  ((b <= 1200)) || { echo "body is $b bytes (over 1,200)" >&2; return 1; }
}

ac2() {
  [[ -f $LESSON ]] || { echo "no lesson at $LESSON" >&2; return 1; }
  # the rule: a moved part or an edge into the owner changes the owner, and an outcome may need the new owner's work
  body | has_all "gives ticket A's part to ticket B" "adds a \`depends_on\` edge from B to A (B waits for A)" \
    "A still reads as the owner" "cannot be built once A must land first" || return 1
  # the incident, by its capture, its answer, the part, the edge, the stranded outcome and the finding
  # each part's final owner, as landed in 0e91b4d7 (not round 1's fix, which F26 overturned)
  body | has_all "2026-11-11 worker idea interview" "0e91b4d7" 'Q3 "c0249 wires it"' "\`rankCommand\`" \
    "c0249 -> c0257" "c0257's captured \"" "c0249's idea review round 1, F5" "c0249 took its rank order" \
    "lost work first stayed c0290's" "a decision line and an Owners line"
}

ac3() {
  [[ -f $LESSON ]] || { echo "no lesson at $LESSON" >&2; return 1; }
  body | has_all "**How to apply:** for each such answer, in the same capture, add to the other ticket's Problem" \
    "a decision line that quotes the option picked" \
    "an Owners line for what you settle beyond it" "Walk its outcomes in the new order" \
    "move each it cannot build to the ticket that can (both texts say so)" \
    "name to the user each ticket whose text it cannot rewrite (past draft, or on a prep branch," \
    "as c0276's Non-goal was in draft PR #281)"
}

ac4() {
  # what the lesson tells is on record (read-only history reads): the capture, c0257's two lines and c0249's F5
  [[ -f $LESSON ]] || { echo "no lesson at $LESSON" >&2; return 1; }
  local g=(git -C "$ZN_ROOT")
  "${g[@]}" cat-file -e 0e91b4d7^{commit} 2>/dev/null || { echo "no commit 0e91b4d7" >&2; return 1; }
  "${g[@]}" log -1 --format=%s 0e91b4d7 | grep -qF "tracker: new " || { echo "0e91b4d7 is not a capture" >&2; return 1; }
  local c57 c49
  c57=$("${g[@]}" show 0e91b4d7:z-nile/.tracker/issues/c0257/c0257.md) || return 1
  has_all 'in c0249'"'"'s idea interview Q3: "c0249 wires it"' "Owners (idea review 002, 2026-11-11)" \
    "the app's rank order (unset last, the ticket number as the tiebreak) and the \`rankCommand\` wiring are c0249's" \
    "lost work first in the app, and its marks, are c0290's (the user, 2026-11-09)" <<<"$c57" || return 1
  # the lesson's quote of c0257's captured outcome, taken from the lesson, is word for word in c0257's capture
  local quote before
  quote=$(body | sed -n "s/.*c0257's captured \"\([^\"]*\)\".*/\1/p" | head -1)
  [[ -n $quote ]] || { echo "the lesson quotes no captured outcome of c0257" >&2; return 1; }
  before=$("${g[@]}" show 0e91b4d7^:z-nile/.tracker/issues/c0257/c0257.md) || return 1
  grep -qF -- "$quote" <<<"$before" || { echo "c0257's capture does not say: $quote" >&2; return 1; }
  c49=$("${g[@]}" show 0e91b4d7:z-nile/.tracker/issues/c0249/c0249.md) || return 1
  has_all "depends_on: [c0265, c0257, c0263]" "### Round 1" \
    "- F5 (medium): Q3 gives the \`rankCommand\` wiring to c0249, but c0257's" \
    "c0276's Non-goal (in its draft PR #281)" <<<"$c49" || return 1
  # F5 sits in round 1 (between the Round 1 and Round 2 headings), and F26, which set the final owners, in round 2
  awk '/^### Round 1$/{r=1;next} /^### Round 2$/{r=0} r&&/^- F5 \(medium\)/{f=1} END{exit !f}' <<<"$c49" ||
    { echo "F5 is not in c0249's idea review round 1" >&2; return 1; }
  awk '/^### Round 2$/{r=1;next} /^### Round 3$/{r=0} r&&/^- F26 \(high\): .*lost first in the app is c0290.s/{f=1} END{exit !f}' <<<"$c49" ||
    { echo "F26 (lost first in the app is c0290's) is not in c0249's idea review round 2" >&2; return 1; }
}

ac5() {
  (cd "$ZN_ROOT" && ./zn lessons --check) || return 1
  (cd "$ZN_ROOT" && ./zn lessons --uncovered c0294) || return 1
  # c0136 adds --unattributed; once it exists every entry of this item's harvest carries its step group
  if grep -qF -- "--unattributed" "$ZN_ROOT/z-nile/engine/main.luau"; then
    (cd "$ZN_ROOT" && ./zn lessons --unattributed c0294) || return 1
  fi
  grep -qE "^- note .*0e91b4d7.*\(erred z-ticket\): ([^ ]+, )*$ID(,|$)" "$HERE/harvest.md" ||
    { echo "harvest.md has no note on 0e91b4d7 naming $ID (erred z-ticket)" >&2; return 1; }
  # read each listing whole before matching: a reader that stops early breaks the engine's pipe
  local out w
  for w in design build; do
    out=$(cd "$ZN_ROOT" && ./zn lessons --when $w) || return 1
    grep -qF -- "- $ID (both, " <<<"$out" || { echo "$ID is not listed for --when $w" >&2; return 1; }
    out=$(cd "$ZN_ROOT" && ./zn lessons --when $w --full) || return 1
    grep -qxF -- "== ${LESSON#"$ZN_ROOT/"}" <<<"$out" || { echo "$ID is not in the $w --full read" >&2; return 1; }
  done
  out=$(cd "$ZN_ROOT" && ./zn lessons --skill z-ticket --full moved-part-rewrites-the-owner) || return 1
  grep -Eq "^sources:.*c0294" <<<"$out" || { echo "c0294 is not on the sources line (the harvest note)" >&2; return 1; }
}

ac6() {
  # c0181 adds lesson states; once lessons.luau reads not_codifiable, this lesson states it and the harvest records it
  if ! grep -qF -- "not_codifiable" "$ZN_ROOT/z-nile/engine/lessons.luau"; then
    echo "c0181 has not landed: no lesson state to check"
    return 0
  fi
  [[ -f $LESSON ]] || { echo "no lesson at $LESSON" >&2; return 1; }
  [[ $(front not_codifiable) == "whether an outcome can still be built in the new order is a reading of what"* ]] ||
    { echo "the lesson has no not_codifiable: line of the reference text" >&2; return 1; }
  grep -qF -- "- codify $ID: not codifiable: " "$HERE/harvest.md" || { echo "harvest.md has no codify line for $ID" >&2; return 1; }
  (cd "$ZN_ROOT" && ./zn lessons --check --policy --item c0294)
}

check "AC1: the lesson z-ticket/moved-part-rewrites-the-owner is short (at most 12 lines besides a distinct_from: line, a body of at most 1,200 bytes), reaches design and build, is tagged capture, dependencies and scope, and keeps the captured check question word for word, adding only the clause on tickets the capture cannot edit" ac1
check "AC2: the lesson states the rule (a moved part or an edge into the owner changes the owner) and tells the 2026-11-11 incident: capture 0e91b4d7, Q3, the rankCommand wiring, c0249 -> c0257, the stranded outcome, F5 and each part's final owner" ac2
check "AC3: the lesson says how to apply it: in the same capture, a decision line quoting the option and an Owners line, the outcomes walked in the new order and moved to who can build them, and each ticket whose text the capture cannot rewrite (past draft, or on a prep branch) named to the user" ac3
check "AC4: what the lesson tells is on record: capture 0e91b4d7, c0257's decision and Owners lines, the lesson's quote word for word in c0257's capture, F5 in round 1 and F26 in round 2 of c0249's idea review" ac4
check "AC5: the lessons tooling accepts the lesson, c0294's harvest note (erred z-ticket) is its source, and both design and build list and read it" ac5
check "AC6: once c0181 has landed, the lesson is not codifiable, the harvest says so, and c0181's policy accepts it" ac6

finish

#!/usr/bin/env bash
# Acceptance checks for c0272. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0272 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0272"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
LESSON="$ZN_ROOT/z-nile/skills/z-design/lessons/superseding-prep-hands-over-the-claim.md"
ID=z-design/superseding-prep-hands-over-the-claim

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
  [[ $(front when) == design ]] || { echo "when: is '$(front when)', not design" >&2; return 1; }
  front tags | has_all coordination claims || return 1
  # the captured question, word for word, then the four additions
  front check | has_all \
    "When I closed or replaced another worker's PR, did I run \`./zn status <id>\` to hand over or release the claim and leave the new branch name on the claim, the issue and the old PR?" \
    "the user's decision" "\`./zn status <id> new\` then \`./zn status <id> preparing\` in the live prep's worktree" \
    "remove the superseded worktrees' claim memories" "dispatched step" || return 1
  local n
  n=$(body | wc -c | tr -d ' ')
  # 1,500: short, under c0181's 2,500-byte cap for a lesson no check enforces
  ((n <= 1500)) || { echo "body is $n bytes (over 1,500)" >&2; return 1; }
}

ac2() {
  body | has_all "c0264" "PR #256" "\`prep-c0264-readme-intent\`" "\`prep-readme-states-znile-intent\`" \
    "the user's decision (zz-rules, Whose claim)" "reached nobody"
}

ac3() {
  # the three places the captured check names, each with the command that writes it, runnable from any worktree
  body | has_all \
    "never judging by a memory's contents" "\`./zn status <id>\`" "\`git worktree list | grep -e <id> -e <slug>\`" \
    "\`ls <main checkout>/.worktree/*/.cache/tracker-claim-<id>\`" \
    "\`./zn dispatch status <id>\`" "\`./zn dispatch stop <id>\`" \
    "in the live prep's worktree, \`./zn status <id> new\`, then \`./zn status <id> preparing\`" \
    "(\`new\` alone releases it)" \
    "\`rm <main checkout>/.worktree/<old>/.cache/tracker-claim-<id>\`" "only memory is in \`.worktree/<live branch>\`" \
    "the old PR's body and a comment (if it has one), then close it" \
    "\`Prep moved (<date>): live on <branch> (PR #<n>)\`" "directly under its \`# <id>: <title>\` heading" \
    "(the newest on top)" "\`capture-<slug>\`" "\`./zn land\`" || return 1
  # the line's place is never a section a prep rewrites
  ! body | grep -qF -- "\`## Design\`" || { echo "the line is placed under ## Design, which a prep rewrites" >&2; return 1; }
}

ac4() {
  # what the lesson names still exists: the claim memory's path, the commands and the zz-rules paragraph
  grep -qF -- '.cache/tracker-claim-{' "$ZN_ROOT/z-nile/engine/main.luau" ||
    { echo "main.luau no longer keeps a claim in .cache/tracker-claim-<id>" >&2; return 1; }
  local help
  # `./zn help` exits 1 by design: read its text, whose lines are what is checked (empty text fails as missing)
  help=$(cd "$ZN_ROOT" && ./zn help 2>&1)
  has_all "  status [<id>] [<to>]" "  dispatch stop|retry|status <id>" "  land [-m <message>]" <<<"$help" || return 1
  grep -qF -- "- **Whose claim.**" "$ZN_ROOT/z-nile/skills/zz-rules/SKILL.md" ||
    { echo "zz-rules has no Whose claim paragraph" >&2; return 1; }
  # a capture may edit a draft backlog issue's sections (the Design line rides `./zn land`)
  grep -qF -- 'a capture edits only the title, depends_on and the sections' "$ZN_ROOT/z-nile/engine/main.luau" ||
    { echo "land's capture scope no longer takes an issue's sections" >&2; return 1; }
}

ac5() {
  (cd "$ZN_ROOT" && ./zn lessons --check) || return 1
  (cd "$ZN_ROOT" && ./zn lessons --uncovered c0272) || return 1
  # c0136 adds --unattributed; once it exists the notes must carry their step group
  if grep -qF -- "--unattributed" "$ZN_ROOT/z-nile/engine/main.luau"; then
    (cd "$ZN_ROOT" && ./zn lessons --unattributed c0272) || return 1
  fi
  grep -qE "^- note .*\(erred z-design\): ([^ ]+, )*$ID(,|$)" "$HERE/harvest.md" ||
    { echo "harvest.md has no note naming $ID (erred z-design)" >&2; return 1; }
  # read whole before matching: a reader that stops early breaks the engine's pipe
  local listed full
  listed=$(cd "$ZN_ROOT" && ./zn lessons --when design) || return 1
  grep -qF -- "- $ID (design, " <<<"$listed" || { echo "$ID is not listed for design" >&2; return 1; }
  full=$(cd "$ZN_ROOT" && ./zn lessons --when design --full) || return 1
  grep -qxF -- "== ${LESSON#"$ZN_ROOT/"}" <<<"$full" || { echo "$ID is not in the design --full read" >&2; return 1; }
}

ac6() {
  # c0181 adds lesson states; once lessons.luau reads not_codifiable, this lesson states it and the harvest records it
  if ! grep -qF -- "not_codifiable" "$ZN_ROOT/z-nile/engine/lessons.luau"; then
    echo "c0181 has not landed: no lesson state to check"
    return 0
  fi
  [[ -n $(front not_codifiable) ]] || { echo "the lesson has no not_codifiable:" >&2; return 1; }
  grep -qF -- "- codify $ID: not codifiable: " "$HERE/harvest.md" || { echo "harvest.md has no codify line for $ID" >&2; return 1; }
  (cd "$ZN_ROOT" && ./zn lessons --check --policy --item c0272)
}

check "AC1: the lesson z-design/superseding-prep-hands-over-the-claim is for design, tagged coordination and claims, keeps the captured question and adds the user's decision, the take-over commands, the removal of stale claim memories and the dispatched step, in a body of at most 1,500 bytes" ac1
check "AC2: the lesson tells the c0264 incident by its two branches and PR #256, and says it runs only on the user's decision (Whose claim)" ac2
check "AC3: the lesson names the holder searches, the stop of a dispatched worker, the take-over or release of the claim in the live worktree and the removal of stale memories, and the live branch named on the old PR and under the issue's title through ./zn land" ac3
check "AC4: the claim memory, the commands, the Whose claim paragraph and land's section edits the lesson names still exist" ac4
check "AC5: the lessons tooling accepts the lesson, c0272's harvest note is its source (erred z-design), and design reads it" ac5
check "AC6: once c0181 has landed, the lesson is not codifiable and the harvest says so" ac6

finish

#!/usr/bin/env bash
# Acceptance checks for c0270. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0270 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0270"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
LESSON="$ZN_ROOT/z-nile/skills/z-design/lessons/one-prep-per-issue.md"
ID=z-design/one-prep-per-issue

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
  # the captured question, word for word, then the three additions
  front check | has_all \
    "Do \`git branch -r --list '*<id>*'\`, \`gh pr list --state all --search <id>\` and \`./zn status <id>\` name another worker or branch for this issue?" \
    "'*<slug>*'" "--repo" "git worktree list" || return 1
  local n
  n=$(body | wc -c | tr -d ' ')
  ((n <= 1200)) || { echo "body is $n bytes (over 1,200)" >&2; return 1; }
}

ac2() {
  body | has_all "c0264" "\`prep-c0264-readme-intent\`" "\`prep-readme-states-znile-intent\`" "PR #256" \
    "**One prep per issue**" "Whose claim" "\`prep-<slug>\`" "--repo"
}

ac3() {
  (cd "$ZN_ROOT" && ./zn lessons --check) || return 1
  (cd "$ZN_ROOT" && ./zn lessons --uncovered c0270) || return 1
  # c0136 adds --unattributed; once it exists the note must carry its step group
  if grep -qF -- "--unattributed" "$ZN_ROOT/z-nile/engine/main.luau"; then
    (cd "$ZN_ROOT" && ./zn lessons --unattributed c0270) || return 1
  fi
  grep -qE "^- note .*\(erred z-design\): ([^ ]+, )*$ID(,|$)" "$HERE/harvest.md" ||
    { echo "harvest.md has no note naming $ID (erred z-design)" >&2; return 1; }
  # listed for design with at least one source
  (cd "$ZN_ROOT" && ./zn lessons --when design) | grep -qE -- "^- $ID \(design, [1-9][0-9]* sources?\)" ||
    { echo "$ID is not listed for design with a source" >&2; return 1; }
}

ac5() {
  # c0181 adds lesson states; once lessons.luau reads not_codifiable, this lesson states it and the harvest records it
  if ! grep -qF -- "not_codifiable" "$ZN_ROOT/z-nile/engine/lessons.luau"; then
    echo "c0181 has not landed: no lesson state to check"
    return 0
  fi
  [[ -n $(front not_codifiable) ]] || { echo "the lesson has no not_codifiable:" >&2; return 1; }
  grep -qF -- "- codify $ID: not codifiable: " "$HERE/harvest.md" || { echo "harvest.md has no codify line for $ID" >&2; return 1; }
  (cd "$ZN_ROOT" && ./zn lessons --check --policy --item c0270)
}

check "AC1: the lesson z-design/one-prep-per-issue is for design, tagged coordination and claims, keeps the captured question and adds the slug, --repo and worktree searches, in a body of at most 1,200 bytes" ac1
check "AC2: the lesson tells the c0264 incident by its two branches and PR #256, and points at step 1's One prep per issue and at Whose claim" ac2
check "AC3: the lessons tooling accepts the lesson, c0270's harvest note is its source (erred z-design), and design reads it" ac3
check "AC4: z-design step 1 states the one-prep rule, its searches, what is yours and what counts as another prep, and what to do with one, headless included" lune run tests/run -- "$A/docs.spec.luau"
check "AC5: once c0181 has landed, the lesson is not codifiable and the harvest says so" ac5

finish

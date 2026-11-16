#!/usr/bin/env bash
# E1: the hand-over the lesson teaches works with today's tools, in a throwaway clone with a bare origin under
# mktemp -d (removed at the end). Three worktrees: `prep-old` claims c0272, `prep-stale` holds a stale memory (as
# c0264's superseded worktree still does), `prep-live` takes the claim over with `status new` then
# `status preparing`, the superseded memories are removed, and a capture worktree lands the lesson's `Prep moved`
# line under the issue's title while both preps hold rewritten documents (the gate overridden: only the publish
# path is under test). Prints what each step showed. Writes nothing outside the temporary folder.
# Run: ./zn run --time 900 -- bash E1-takeover.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd -P)"
top="$(git -C "$here" rev-parse --show-toplevel)"
t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT
# a dispatched step's publish broker pushes to the real origin: the clone must never see it, the step's git
# wrapper, run state or credential (lesson z-design/clone-experiments-drop-the-step-environment)
for v in $(compgen -e | grep '^ZN_'); do unset "$v"; done
unset GH_CONFIG_DIR
PATH=$(tr ':' '\n' <<<"$PATH" | grep -v '/z-nile/bin$' | paste -sd: -)
export GIT_AUTHOR_NAME=e1 GIT_AUTHOR_EMAIL=e1@example.invalid GIT_COMMITTER_NAME=e1 GIT_COMMITTER_EMAIL=e1@example.invalid
git clone -q --bare --no-local "$top" "$t/origin.git"
git -C "$t/origin.git" update-ref refs/heads/main "$(git -C "$top" rev-parse HEAD)"
git clone -q "$t/origin.git" "$t/repo"
cd "$t/repo" || exit 1
git checkout -q main
# refuse to publish anywhere but the bare origin in the temporary folder
case "$(git remote get-url origin)" in "$t"/*) ;; *) echo "E1 refused: origin is not under $t"; exit 2 ;; esac
env | grep -q '^ZN_' && { echo "E1 refused: a ZN_ variable is still set"; exit 2; }
D=z-nile/.tracker/issues/c0272/c0272.md
for w in prep-old prep-live prep-stale; do git worktree add -q -b "$w" ".worktree/$w" origin/main; done
mkdir -p .worktree/prep-stale/.cache && echo new-stale-stamp-words > .worktree/prep-stale/.cache/tracker-claim-c0272
stampOn() { git -C "$t/repo" fetch -q origin main && git -C "$t/repo" show "origin/main:$D" | sed -n 's/^status: //p'; }
(cd .worktree/prep-old && ./zn status c0272 new >/dev/null && ./zn status c0272 preparing) || { echo "E1 FAIL: old could not claim"; exit 1; }
s1=$(stampOn)
echo "old claims: origin/main $s1, old remembers $(cat .worktree/prep-old/.cache/tracker-claim-c0272)"
# each prep rewrites its own document (frontmatter, Non-goals, Design), with different text, and commits it
rewrite() { # <worktree> <word>
  (
    cd "$1" || exit 1
    ./zn sync >/dev/null 2>&1
    awk -v w="$2" '
      /^emergent: false$/ {print; print "size: 13"; next}
      /^design: draft$/ {print "design: reviewed"; next}
      /^## Non-goals$/ {print; print "- the " w " prep fences this."; skip=1; next}
      /^## Design$/ {print; print "The " w " prep designs it this way."; skip=1; next}
      /^## / {skip=0}
      !skip {print}' "$D" > "$t/rw" && cat "$t/rw" > "$D"
    git commit -qam "wip: $2 prep's design"
  )
}
rewrite .worktree/prep-old old
rewrite .worktree/prep-live live
# the search, from inside a worktree, in the lesson's form: every candidate is listed
M="$t/repo" # <main checkout>
(cd .worktree/prep-live && ls "$M"/.worktree/*/.cache/tracker-claim-c0272) | sed "s#$M/##; s/^/candidate before: /"
(cd .worktree/prep-live && ./zn status c0272 preparing 2>&1) | sed 's/^/live claims without giving back first: /'
(cd .worktree/prep-live && ./zn status c0272 new >/dev/null && ./zn status c0272 preparing) || { echo "E1 FAIL: live could not take over"; exit 1; }
s2=$(stampOn); m2=$(cat .worktree/prep-live/.cache/tracker-claim-c0272)
echo "live takes over: origin/main $s2, live remembers $m2, old still remembers $(cat .worktree/prep-old/.cache/tracker-claim-c0272)"
[[ $s2 == "$m2" && $s2 != "$s1" ]] && echo "E1a PASS: the stamp is the live worktree's" || echo "E1a FAIL"
# remove each superseded worktree's memory: the listing then names only the live branch
(cd .worktree/prep-live && rm "$M/.worktree/prep-old/.cache/tracker-claim-c0272" "$M/.worktree/prep-stale/.cache/tracker-claim-c0272")
left=$(cd .worktree/prep-live && ls "$M"/.worktree/*/.cache/tracker-claim-c0272 | sed "s#$M/##")
[[ $left == ".worktree/prep-live/.cache/tracker-claim-c0272" ]] && echo "E1b PASS: the only memory is in .worktree/prep-live" || echo "E1b FAIL: $left"
# the capture lands the lesson's line directly under the title, while both preps hold rewritten documents
git worktree add -q -b capture-c0272-moved .worktree/capture-c0272-moved origin/main
LINE='Prep moved (2026-11-15): live on prep-live (PR #999)'
(
  cd .worktree/capture-c0272-moved || exit 1
  awk -v l="$LINE" '{print} /^# c0272: /{print ""; print l}' "$D" > "$t/cap" && cat "$t/cap" > "$D"
  git commit -qam "tracker: c0272 prep moved to prep-live"
  PICKMAN_LAND_GATE=true ./zn land > "$t/land" 2>&1 && echo "land: ok" || { echo "land: FAILED"; tail -3 "$t/land"; }
)
git fetch -q origin main
git show "origin/main:$D" | grep -qxF "$LINE" && echo "E1c PASS: origin/main's document holds the line" || echo "E1c FAIL"
for w in prep-old prep-live; do
  (
    cd ".worktree/$w" || exit 1
    if ./zn sync >"$t/sync" 2>&1; then r=ok; else r="FAILED: $(tail -1 "$t/sync")"; fi
    echo "E1d $w: sync $r, holds the line $(grep -cxF "$LINE" "$D"), keeps its own Design $(grep -c "^The ${w#prep-} prep designs it" "$D")"
  )
done
(cd .worktree/prep-live && ./zn capture c0272 2>&1 | head -1 | sed 's/^/E1e capture: /')
echo "E1f stamp after land: $(stampOn) (unchanged: $([[ $(stampOn) == "$s2" ]] && echo yes || echo no)); status: $(cd .worktree/prep-live && ./zn status c0272)"
(cd .worktree/prep-live && ./zn lessons --check 2>&1 | tail -1 | sed 's/^/E1g /')

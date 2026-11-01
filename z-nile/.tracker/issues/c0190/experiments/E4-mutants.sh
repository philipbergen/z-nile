#!/usr/bin/env bash
# c0190's capture-history mutants, run in a prototype: a scratch clone of the repository whose origin is a local bare
# repository, both outside the real checkout. It resets, cleans and force-pushes that clone's origin, so it refuses
# anything else (design review 003 F2).
#   bash E4-mutants.sh <prototype clone>
set -u
REAL_TOP=$(git -C "$(dirname "$0")" rev-parse --show-toplevel) || exit 1
REAL_GIT=$(git -C "$REAL_TOP" rev-parse --path-format=absolute --git-common-dir) || exit 1
refuse() { echo "E4-mutants: $*; refusing" >&2; exit 1; }
[[ $# -eq 1 && -n $1 && -d $1 ]] || refuse "usage: E4-mutants.sh <prototype clone>"
CLONE=$(cd "$1" && pwd -P) || exit 1
case "$CLONE/" in "$REAL_TOP"/*) refuse "$CLONE is inside the real checkout" ;; esac
[[ $(git -C "$CLONE" rev-parse --show-toplevel 2>/dev/null) == "$CLONE" ]] || refuse "$CLONE is not the top of a git clone"
[[ $(git -C "$CLONE" rev-parse --path-format=absolute --git-common-dir) != "$REAL_GIT" ]] || refuse "$CLONE shares the real repository"
ORIGIN=$(git -C "$CLONE" remote get-url origin 2>/dev/null) || refuse "$CLONE has no origin"
[[ -d $ORIGIN && $(git -C "$ORIGIN" rev-parse --is-bare-repository 2>/dev/null) == true ]] || refuse "origin $ORIGIN is not a local bare repository"
ORIGIN=$(cd "$ORIGIN" && pwd -P)
case "$ORIGIN/" in "$REAL_TOP"/* | "$REAL_GIT"/*) refuse "origin $ORIGIN is inside the real repository" ;; esac
cd "$CLONE" || exit 1
export PICKMAN_FENCE_REAL_GIT=$REAL_GIT
git reset -q --hard; git clean -fdq; git checkout -q main; git reset -q --hard origin/main
G=$(git rev-parse HEAD)
# the capture: the newest commit whose subject is `tracker: new` and 27 ids
Cc=$(git log --format='%H %s' | awk '$2 == "tracker:" && $3 == "new" && NF == 30 { print $1; exit }')
[[ -n $Cc ]] || refuse "no capture commit (tracker: new and 27 ids) in $CLONE"
B=$(git rev-parse "$Cc^"); SUBJ=$(git log -1 --format=%s "$Cc")
gc() { git -c user.email=proto@localhost -c user.name=proto commit -qam "$1"; }
d() { grep -lx "slug: $2" "$1"/.tracker/issues/*/*.md; }
idk() { basename "$(d "$1" "$2")" .md; }
mut() { # $1 name; $2 edit of the capture tree; $3 commits after the capture (optional)
	git checkout -q --detach "$Cc"; git reset -q --soft "$B"; $2; gc "$SUBJ"; [[ -n ${3:-} ]] && $3
	git checkout -q "$G" -- z-nile/.tracker/issues/c0190; gc "proto: c0190 checks"
	git push -qf origin HEAD:main; echo "== $1"
	./zn check c0190 2>&1 | grep -E '^(FAIL|---- )|^      [a-zA-Z]' | grep -v "^      FAIL" | head -3
	git checkout -q main; git reset -q --hard "$G"; git push -qf origin "$G:main"; }
none() { :; }
thin() { python3 -c "import re,sys;p=sys.argv[1];t=open(p).read();t=re.sub(r'\n- Snake.s runs go[^\n]*','\n- Snake has scores.',t);open(p,'w').write(t)" "$(d snake snake-scores-and-revives)"; }
fixit() { git checkout -q "$Cc" -- "$(d snake snake-scores-and-revives)"; gc "tracker: fix S5 text"; }
a1() { sed -i '' 's/^depends_on: \[c0185\]$/depends_on: []/' "$(d arcade hiscores-with-revives)"; }
z3() { sed -i '' "s/, $(idk portal play-buttons)\]/]/" "$(d portal n-place-deploy)"; }
c188() { sed -i '' "s/, $(idk portal n-place-deploy)\]/]/" "$(d pickman retire-lobby-place)"; }
i3() { sed -i '' "s/\[\([^]]*\)$(idk invaders invaders-two-players), /[\1/" "$(d invaders invaders-cannon-view)"; }
s3() { sed -i '' "s/, $(idk arcade input-and-look-cores)\]/]/" "$(d snake snake-first-person-view)"; }
halfB() { # the snake issues out of the capture, landed by a second commit
	for f in snake/.tracker/issues/*/f*.md; do git show "$B:$f" > "$f"; done; }
halfC() { git checkout -q "$Cc" -- snake/.tracker/issues; gc "tracker: new $(for f in snake/.tracker/issues/*/f*.md; do basename "$f" .md; done | tr '\n' ' ')snake"; }
prepedit() { p=$(d snake arena-maps-growth); sed -i '' 's/^depends_on: \[c0184\]$/depends_on: [c0184, f0195]/' "$p"; echo "- Prep detail." >> "$p"; gc "tracker: prep S1 detail"; }
wrongid() { sed -i '' "s/^- The boards' store: $(idk arcade hiscores-with-revives)\.$/- The boards' store: $(idk arcade shared-travel)./" "$(d snake snake-scores-and-revives)"; }
s5s3() { sed -i '' "s/, $(idk snake snake-first-person-view)//" "$(d snake snake-scores-and-revives)"; }
i4i3() { sed -i '' "s/, $(idk invaders invaders-cannon-view)//" "$(d invaders invaders-scores-and-revives)"; }
mut "correct" none
mut "thin capture, later fix commit" thin fixit
mut "two lands" halfB halfC
mut "A1 without c0185" a1
mut "Z3 without P4" z3
mut "c0188 without Z3" c188
mut "I3 without I2" i3
mut "S3 without A4" s3
mut "S5's Non-goals naming A2's id for the boards' store" wrongid
mut "S5 without S3" s5s3
mut "I4 without I3" i4i3
mut "a prep edits S1 after the land (stays green)" none prepedit

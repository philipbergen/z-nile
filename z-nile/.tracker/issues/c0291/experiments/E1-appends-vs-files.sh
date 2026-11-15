#!/usr/bin/env bash
# c0291 E1: in a throwaway repo under $TMPDIR, (a) two branches that each append a paragraph to the end of one lesson
# conflict (the problem), (b) two branches that each add a note file to the lesson's notes folder merge cleanly, in
# `git merge` and in `git merge-tree --write-tree`, and (c) two note files of one name with different texts conflict
# (add/add), so a note is never overwritten silently. Run: ./zn run --time 60 -- bash <this file>
set -u
dir=$(mktemp -d "${TMPDIR:-/tmp}/c0291-e1.XXXXXX")
cd "$dir" && git init -q -b main . && git config user.name e1 && git config user.email e1@example.invalid
mkdir -p skills/s/lessons && printf -- '---\ntitle: t\n---\nThe rule.\n' > skills/s/lessons/l.md
git add -A && git commit -qm seed
try() { # $1 label; $2 setup-a; $3 setup-b
  git checkout -q main && git checkout -qb "a-$1" && eval "$2" && git add -A && git commit -qm a
  git checkout -q main && git checkout -qb "b-$1" && eval "$3" && git add -A && git commit -qm b
  git merge-tree --write-tree "a-$1" "b-$1" >/dev/null; mt=$?
  if git merge -q --no-edit "a-$1" >/dev/null 2>&1; then m=clean; else m=conflict; git merge --abort; fi
  echo "$1: merge-tree exit $mt, merge $m"
}
try append 'printf "\nNote A.\n" >> skills/s/lessons/l.md' 'printf "\nNote B.\n" >> skills/s/lessons/l.md'
try files 'mkdir -p skills/s/lessons/l && echo A > skills/s/lessons/l/2026-11-09-a.md' 'mkdir -p skills/s/lessons/l && echo B > skills/s/lessons/l/2026-11-09-b.md'
try samename 'mkdir -p skills/s/lessons/l && echo A > skills/s/lessons/l/2026-11-10-x.md' 'mkdir -p skills/s/lessons/l && echo B > skills/s/lessons/l/2026-11-10-x.md'
rm -rf "$dir"

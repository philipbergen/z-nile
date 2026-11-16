#!/bin/sh
# E11 (c0189): routes onto an old fixture-tip branch, and the push of one to a remote. Throwaway repos under $TMPDIR only.
set -u
HOOK=$1
T=$(mktemp -d "${TMPDIR:-/tmp}/c0189-e11.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
cd "$T" && git init -q -b main repo && git init -q --bare remote.git && cd repo
git config user.email real@x.test; git config user.name real
git remote add origin ../remote.git
git commit -q --allow-empty -m base
git push -q origin main 2>/dev/null
git -c user.email=p@example.invalid commit -q --allow-empty -m proto
git branch old-proto; git reset -q --hard HEAD~1
cp "$HOOK" .git/hooks/reference-transaction; chmod +x .git/hooks/reference-transaction
t() { d=$1; shift; out=$("$@" 2>&1 </dev/null); echo "$d -> exit=$?"; }
t "checkout --detach old-proto" git checkout --detach old-proto
git checkout -q main
t "switch -c from-old old-proto" git switch -c from-old old-proto
t "worktree add --detach ../w1 old-proto" git worktree add --detach ../w1 old-proto
t "merge --ff-only old-proto" git merge --ff-only old-proto
t "worktree add ../w2 old-proto (the branch itself)" git worktree add ../w2 old-proto
t "push origin old-proto (a branch made before the hook)" git push origin old-proto
echo "remote now has: $(git --git-dir=../remote.git for-each-ref --format='%(refname)' | tr '\n' ' ')"
t "fetch origin afterwards" git fetch origin

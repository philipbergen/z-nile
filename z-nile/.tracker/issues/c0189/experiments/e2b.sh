#!/bin/sh
# E2b/E3 (c0189): behaviour of the prototype hook and its cost. Throwaway repos under $TMPDIR only.
set -u
HOOK=$1
T=$(mktemp -d "${TMPDIR:-/tmp}/c0189-e2b.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
cd "$T" || exit 1
git init -q -b main repo && git init -q --bare remote.git
cd repo
git config user.email real@x.test; git config user.name real
git remote add origin ../remote.git
git commit -q --allow-empty -m base
git push -q origin main 2>/dev/null
cp "$HOOK" .git/hooks/reference-transaction; chmod +x .git/hooks/reference-transaction
show() { echo "-- $1 -> exit=$2"; }
run() { desc=$1; shift; out=$("$@" 2>&1); rc=$?; show "$desc" $rc; [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/     /' | cut -c1-230; }
head0=$(git rev-parse HEAD)
run "commit as real" git commit -q --allow-empty -m real
run "commit author fixture" git -c user.email=x@example.invalid commit -q --allow-empty -m fx
echo "     HEAD moved? $( [ "$(git rev-parse HEAD)" = "$(git rev-parse HEAD)" ] && git log --format=%ae -1)"
run "commit committer only fixture" env GIT_COMMITTER_EMAIL=c@EXAMPLE.invalid git commit -q --allow-empty -m cfx
run "commit author-only fixture" env GIT_AUTHOR_EMAIL=a@example.invalid git commit -q --allow-empty -m afx
# a fixture commit object that no ref points at
fx=$(GIT_AUTHOR_EMAIL=a@example.invalid GIT_COMMITTER_EMAIL=a@example.invalid git commit-tree -m fixture "$(git write-tree)" -p HEAD)
run "branch at fixture commit" git branch bad $fx
run "update-ref at fixture commit" git update-ref refs/heads/bad2 $fx
run "tag at fixture commit" git tag tbad $fx
run "worktree add -b at fixture commit" git worktree add -q -b wbad ../wbad $fx
echo "     leftover worktree dir? $(ls -d ../wbad 2>/dev/null) ; wbad branch? $(git branch --list wbad)"
git worktree prune
run "worktree add -b at real commit" git worktree add -q -b wok ../wok HEAD
run "commit in linked worktree as fixture" git -C ../wok -c user.email=x@example.invalid commit -q --allow-empty -m fx2
run "detached commit in linked worktree as fixture" sh -c "git -C ../wok checkout -q --detach && git -C ../wok -c user.email=x@example.invalid commit -q --allow-empty -m fx3"
# existing fixture branch: no-op and deletion allowed
git -c core.hooksPath=/dev/null update-ref refs/heads/old $fx
run "no-op update of an existing fixture branch" git update-ref refs/heads/old $fx
run "delete the fixture branch" git branch -D old
git -c core.hooksPath=/dev/null update-ref refs/heads/old $fx
run "checkout the fixture branch (symbolic HEAD)" git -C ../wok checkout -q old
run "real commit on top of fixture branch" git -C ../wok commit -q --allow-empty -m ontop
# fetch: remote has one fixture-tip branch and one normal
git clone -q ../remote.git ../other; git -C ../other config user.email o@x.test; git -C ../other config user.name o
git -C ../other commit -q --allow-empty -m n1; git -C ../other push -q origin HEAD:refs/heads/okbranch
git -C ../other -c user.email=x@example.invalid commit -q --allow-empty -m n2; git -C ../other push -q origin HEAD:refs/heads/fxbranch
run "fetch with one fixture-tip branch" git fetch origin
echo "     remote refs after: $(git for-each-ref --format='%(refname)' refs/remotes | tr '\n' ' ')"
run "cherry-pick fixture-authored commit" git cherry-pick $fx
run "stash" sh -c "echo z > zz && git add zz && git stash push -q"
# E3: cost
bench() { n=$1; shift; s=$(perl -MTime::HiRes=time -e 'print time'); i=0; while [ $i -lt $n ]; do "$@" >/dev/null 2>&1; i=$((i+1)); done; e=$(perl -MTime::HiRes=time -e 'print time'); perl -e "printf \"%.1f ms per op\n\", ($e-$s)*1000/$n"; }
git checkout -q -B bench main 2>/dev/null
echo "E3 skipped"; exit 0
echo "E3 with hook:"; bench 60 git commit -q --allow-empty -m b
echo "E3 with hook, update-ref:"; bench 60 git update-ref refs/heads/p HEAD
rm .git/hooks/reference-transaction
echo "E3 without hook:"; bench 60 git commit -q --allow-empty -m b
echo "E3 without hook, update-ref:"; bench 60 git update-ref refs/heads/p HEAD

#!/bin/sh
set -u
HOOK=$1
T=$(mktemp -d "${TMPDIR:-/tmp}/c0189-e2d.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
cd "$T" && git init -q -b main repo && git init -q --bare remote.git && cd repo
git config user.email real@x.test; git config user.name real
git remote add origin ../remote.git
git commit -q --allow-empty -m base; git push -q origin main 2>/dev/null
cp "$HOOK" .git/hooks/reference-transaction; chmod +x .git/hooks/reference-transaction
git clone -q ../remote.git ../other; cd ../other; git config user.email o@x.test; git config user.name o
for b in a-ok; do git commit -q --allow-empty -m $b; git push -q origin HEAD:refs/heads/$b; done
git -c user.email=x@example.invalid commit -q --allow-empty -m fx; git push -q origin HEAD:refs/heads/m-fixture
git -c user.email=o@x.test commit -q --allow-empty -m z; git push -q origin HEAD:refs/heads/z-ok
cd ../repo
git fetch origin 2>&1 | cut -c1-120 | grep -v 'Fixture\|reference-trans'; echo "fetch rc=$?"
echo "after: $(git for-each-ref --format='%(refname)' refs/remotes | tr '\n' ' ')"
echo "== atomic"; git fetch --atomic origin 2>&1 | tail -2 | cut -c1-100
echo "== worktree add of an existing fixture-tip branch and stash/checkout on it"
fx=$(GIT_AUTHOR_EMAIL=a@example.invalid GIT_COMMITTER_EMAIL=a@example.invalid git commit-tree -m fixture "$(git write-tree)" -p HEAD)
git -c core.hooksPath=/dev/null update-ref refs/heads/legacy $fx
git worktree add -q ../wl legacy 2>&1 | cut -c1-100; echo "worktree add rc=$?"
cd ../wl; echo z > z; git add z; git stash push -q 2>&1 | cut -c1-100; echo "stash rc=$?"
git checkout -q main 2>&1 | head -2; git checkout -q legacy 2>&1 | head -2; echo "checkouts done: $(git branch --show-current)"
git -c user.email=real@x.test commit -q --allow-empty -m on-top 2>&1 | head -3; echo "commit-on-top rc=$?"
git -c user.email=x@example.invalid commit -q --allow-empty -m again 2>&1 | head -2 | cut -c1-80

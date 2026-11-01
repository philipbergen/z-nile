#!/bin/sh
# E2 (c0189): which git operations run reference-transaction, and with what input. Throwaway repo under $TMPDIR only.
set -u
T=$(mktemp -d "${TMPDIR:-/tmp}/c0189-e2.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
cd "$T" || exit 1
git init -q -b main repo && git init -q --bare remote.git
cd repo
git config user.email real@x.test; git config user.name real
git remote add origin ../remote.git
cat > .git/hooks/reference-transaction <<'H'
#!/bin/sh
{ printf '[%s]' "$1"; while read -r o n r; do printf ' %s->%s %s;' "$(echo $o | cut -c1-4)" "$(echo $n | cut -c1-4)" "$r"; done; echo; } >> "$LOG"
exit 0
H
chmod +x .git/hooks/reference-transaction
export LOG=$T/log
step() { : > "$LOG"; echo "## $*"; "$@" >/dev/null 2>&1; echo "exit=$?"; cut -c1-200 "$LOG" | grep -v '^\[\(aborted\|committed\)\]' ; }
step git commit --allow-empty -m one
git push -q origin main 2>/dev/null
step git branch topic
step git update-ref refs/heads/up HEAD
step git worktree add -b wt ../wt1
step git -C ../wt1 commit --allow-empty -m wtcommit
step git -C ../wt1 checkout -q --detach
step git -C ../wt1 commit --allow-empty -m detached
# a second clone pushes a new branch; then fetch here
git clone -q ../remote.git ../other 2>/dev/null; git -C ../other config user.email o@x.test; git -C ../other config user.name o
git -C ../other commit -q --allow-empty -m fromother; git -C ../other push -q origin HEAD:refs/heads/newbranch 2>/dev/null
git -C ../other push -q origin HEAD:main 2>/dev/null
step git fetch origin
step git fetch origin
step git push origin topic
step git tag v1
step git branch -D topic
step git stash list
echo x > f; git add f
step git stash push -u
step git merge --ff-only origin/main
step git cherry-pick origin/newbranch
step git rebase origin/main
step git pull --ff-only origin main
step git reset --hard HEAD~1
echo "## clone of this repo (does a clone copy hooks?)"; git clone -q . ../cl 2>/dev/null; ls ../cl/.git/hooks | grep -c -v sample

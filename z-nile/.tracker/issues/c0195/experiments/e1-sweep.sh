#!/usr/bin/env bash
# E1 (c0195): which ref-writing git commands change refs in a fenced "real" repository? Each command runs in a
# fresh copy of a throwaway repository under $TMPDIR, fenced by z-nile/lib/fence.sh exactly as ac.sh fences a
# checkout (mode checks; with E1_MODE=specs, as the runner does without a jail). A logging hook beside the guard
# records what reference-transaction saw. Reports: exit, whether the refs/HEAD/worktrees changed, and the hook log.
# Usage: e1-sweep.sh <git binary> [<fence.sh>]   (a prototype's fence.sh to run the sweep with the fix in)
set -u
GITBIN=${1:?git binary}
FENCE=${2:-$(cd "$(dirname "$0")/../../../../lib" && pwd -P)/fence.sh}
T=$(mktemp -d "${TMPDIR:-/tmp}/c0195-e1.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
# a wrapper, not a link: a linked git looks for its templates beside the link
mkdir "$T/bin" && printf '#!/bin/sh\nexec "%s" "$@"\n' "$GITBIN" >"$T/bin/git" && chmod +x "$T/bin/git"
export PATH="$T/bin:/usr/bin:/bin" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG_COUNT GIT_CEILING_DIRECTORIES PICKMAN_FENCE_REAL_GIT \
  PICKMAN_FENCE_HOOKS PICKMAN_FENCE_SPECS PICKMAN_TEST_FENCE PICKMAN_TEST_JAIL
echo "# $(git --version), mode ${E1_MODE:-checks}"
# the base repository: main, a side branch, a remote with a tracking ref, a tag
git init -q -b main "$T/base" && cd "$T/base" || exit 1
git config user.email real@x.test && git config user.name real
echo a >f && git add f && git commit -qm base && echo b >f && git commit -qam second
git branch side HEAD~1 && git tag v1 HEAD~1
git init -q --bare "$T/remote.git" && git remote add origin "$T/remote.git" && git push -q origin main 2>/dev/null
git fetch -q origin && git remote set-head origin main >/dev/null
mkdir -p .git/info && printf '.cache/\n' >.git/info/exclude
state() { # refs (incl. symrefs), HEAD, packed-refs, worktrees and reflogs of the repo, with an unfenced git
  env -u GIT_CONFIG_COUNT -u GIT_CEILING_DIRECTORIES git -C "$1" for-each-ref --format='%(refname) %(objectname) %(symref)'
  echo "HEAD: $(cat "$1/.git/HEAD" 2>/dev/null)"
  echo "format: $(env -u GIT_CONFIG_COUNT git -C "$1" rev-parse --show-ref-format 2>/dev/null)"
  env -u GIT_CONFIG_COUNT -u GIT_CEILING_DIRECTORIES git -C "$1" worktree list --porcelain | grep '^worktree'
  echo "loose: $(cd "$1/.git" && find refs -type f | sort | tr '\n' ' ')"
  echo "logs: $(cd "$1/.git" && find logs -type f 2>/dev/null | sort | tr '\n' ' ')"
  echo "config: $(env -u GIT_CONFIG_COUNT git -C "$1" config --local --list | grep -v '^core\.' | tr '\n' ' ')"
}
run() { # <label> <shell command>
  local r="$T/r$((++n))"
  cp -R "$T/base" "$r"
  state "$r" >"$T/before"
  : >"$T/log"
  ( cd "$r" && source "$FENCE" && pickman_fence "$r" ${E1_MODE:-checks} >/dev/null 2>&1 || { echo FENCE-FAILED; exit 9; }
    # the logging hook: a copy of the guard's folder with a logger in front of reference-transaction
    cp -R "$PICKMAN_FENCE_HOOKS" "$T/hooks$n" && mv "$T/hooks$n/reference-transaction" "$T/hooks$n/rt-guard"
    printf '#!/bin/sh\ni=$(cat); printf "[%%s] %%s\\n" "$1" "$(printf "%%s" "$i" | awk "{print substr(\\$1,1,4)\\"->\\"substr(\\$2,1,4),\\$3}" | tr "\\n" ";")" >>"%s"\nprintf "%%s\\n" "$i" | "${0%%/*}/rt-guard" "$@"\n' "$T/log" >"$T/hooks$n/reference-transaction"
    chmod +x "$T/hooks$n/reference-transaction"
    export GIT_CONFIG_VALUE_0="$T/hooks$n" PICKMAN_FENCE_HOOKS="$T/hooks$n"
    eval "$2" >"$T/out" 2>&1; echo $? >"$T/rc" )
  state "$r" >"$T/after"
  local changed=no; cmp -s "$T/before" "$T/after" || changed=YES
  printf '%-44s exit=%-3s changed=%-4s hook: %s\n' "$1" "$(cat "$T/rc" 2>/dev/null)" "$changed" \
    "$(grep -E '^\[(prepared|preparing)\]' "$T/log" | grep prepared | tr '\n' ' ' | cut -c1-110)"
  [[ $changed == YES ]] && diff "$T/before" "$T/after" | grep '^[<>]' | sed 's/^/      /' | head -6
  [[ ${E1_VERBOSE:-} ]] && sed 's/^/      out: /' "$T/out" | head -4
  rm -rf "$r"
}
n=0
run "branch new (control)" "git branch new"
run "branch -c main evil" "git branch -c main evil"
run "branch -C main side" "git branch -C main side"
run "branch -c (current) evil2" "git branch -c evil2"
run "branch -m side moved" "git branch -m side moved"
run "branch -M side main2" "git branch -M side main2"
run "branch -m main renamed (current)" "git branch -m renamed"
run "symbolic-ref HEAD refs/heads/side" "git symbolic-ref HEAD refs/heads/side"
run "symbolic-ref refs/heads/sym refs/heads/main" "git symbolic-ref refs/heads/sym refs/heads/main"
run "symbolic-ref -d refs/remotes/origin/HEAD" "git symbolic-ref -d refs/remotes/origin/HEAD"
run "branch --copy main evil" "git branch --copy main evil"
run "branch -f side main" "git branch -f side main"
run "checkout -B side" "git checkout -q -B side"
run "switch -C side" "git switch -q -C side"
run "rebase --update-refs" "git rebase -q --update-refs side"
run "remote set-head origin main" "git remote set-head origin main"
run "checkout side" "git checkout -q side"
run "checkout -b nb" "git checkout -q -b nb"
run "checkout --orphan orph" "git checkout -q --orphan orph"
run "switch --orphan orph" "git switch -q --orphan orph"
run "checkout --detach" "git checkout -q --detach"
run "update-ref refs/heads/x HEAD" "git update-ref refs/heads/x HEAD"
run "tag t2" "git tag t2"
run "remote rename origin o2" "git remote rename origin o2"
run "remote rename --no-progress origin o2 refs" "git remote rename origin o2; git for-each-ref refs/remotes"
run "remote remove origin" "git remote remove origin"
run "pack-refs --all" "git pack-refs --all"
run "refs migrate --ref-format=reftable" "git refs migrate --ref-format=reftable"
run "stash" "echo c >f; git stash -q"
run "notes add" "git notes add -m n HEAD"
run "replace" "git replace HEAD HEAD~1"
run "worktree add -b wt .cache/wt" "git worktree add -q -b wt .cache/wt"
run "worktree add --detach .cache/wt" "git worktree add -q --detach .cache/wt HEAD"
run "fast-import" "printf 'reset refs/heads/fi\nfrom refs/heads/main\n\n' | git fast-import --quiet"
run "fetch . main:refs/heads/fetched" "git fetch -q . main:refs/heads/fetched"
run "fetch . main:refs/remotes/x/y" "git fetch -q . main:refs/remotes/x/y"
run "push . main:refs/heads/pushed" "git push -q . main:refs/heads/pushed"
run "replay --onto side main~1..main" "git replay --onto side main~1..main"
run "replay --ref-action=update" "git replay --ref-action=update --onto side main~1..main"
run "rebase side (no-op ff)" "git rebase -q side"
run "commit" "git commit -q --allow-empty -m x"
run "reset --hard HEAD~1" "git reset -q --hard HEAD~1"
run "reflog delete" "git reflog delete HEAD@{0}"
run "reflog expire --all" "git reflog expire --expire=now --all"
run "gc --prune=now" "git gc -q --prune=now"
run "init (reinit) -b other" "git init -q -b other"
run "clone --bare . into .cache (control)" "git clone -q --bare . .cache/c.git"
run "mv refs file by hand (control: not git)" "cp .git/refs/heads/side .git/refs/heads/byhand"

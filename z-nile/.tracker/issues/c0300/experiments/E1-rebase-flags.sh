#!/usr/bin/env bash
# c0300 E1/E2: what `git rebase --reapply-cherry-picks --empty=keep --onto <new> <upstream>` does on a
# detached HEAD, and whether a -U0 diff with its index and @@ lines dropped is the same before and
# after a clean rebase that moves the commit's context and line numbers. Throwaway repo under .cache.
set -euo pipefail
top="$(git rev-parse --show-toplevel)"
d="$top/.cache/c0300-e1"
rm -rf "$d"; mkdir -p "$d"; cd "$d"
git init -q -b main .
git config user.name e1; git config user.email e1@example.invalid
key() { git diff-tree -p -U0 --binary --full-index --no-renames --no-commit-id -r "$1" | { grep -v '^index ' || true; } | sed -E 's/^@@ .*/@@/'; }
seq 1 20 > f.txt; printf 'x' > bin.dat; printf 'abc\0def' > blob.bin
git add -A; git commit -qm base
git switch -qc layer
git commit -q --allow-empty -m "tracker: start R0010 x"
sed -i '' 's/^10$/ten/' f.txt; git commit -qam "c0010: one"
printf 'abc\0XYZ' > blob.bin; git commit -qam "c0010: binary"
echo dup > dup.txt; git add dup.txt; git commit -qm "c0010: dup"
git commit -q --allow-empty -m "c0010: still working"
git switch -q main
sed -i '' 's/^1$/one/; s/^7$/seven/' f.txt   # line 7 (in -U3 context, two lines off) and line numbers above move
printf '0\n' | cat - f.txt > f2 && mv f2 f.txt
echo dup > dup.txt; git add -A; git commit -qm "main moves, and carries dup"
before=(); for c in $(git rev-list --reverse main..layer); do before+=("$(git log -1 --format=%s "$c")|$(key "$c" | shasum | cut -c1-12)"); done
git switch -q --detach layer
git rebase --quiet --reapply-cherry-picks --empty=keep --onto main "$(git merge-base main layer)" 2>&1 || true
after=(); for c in $(git rev-list --reverse main..HEAD); do after+=("$(git log -1 --format=%s "$c")|$(key "$c" | shasum | cut -c1-12)"); done
echo "branch layer still at its old tip: $([[ $(git rev-parse layer) == $(git rev-parse layer@{0}) ]] && git log -1 --format=%s layer)"
echo "before: ${before[*]}"
echo "after:  ${after[*]}"
echo "empty key: $(printf '' | shasum | cut -c1-12)"
echo "HEAD detached: $(git branch --show-current | wc -c | tr -d ' ') (1 = detached)"
echo "default rebase (no flags) of the same layer:"
git switch -q --detach layer
git rebase --quiet --onto main "$(git merge-base main layer)" 2>&1 || true
git log --reverse --format='  %s' main..HEAD

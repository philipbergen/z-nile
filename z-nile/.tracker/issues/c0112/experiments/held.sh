#!/usr/bin/env bash
# c0112: which items' ledgers are being written by someone else right now. Fails closed: when an input cannot be read it
# exits 2 and says so, never printing a shorter list. It fetches refs/remotes only (origin's main, each open PR's head).
#   held.sh <repo> [<days>]
# An item is held when (a) its folder is under active/ on origin/main, or (b) its harvest.md differs from origin/main's on
# the head of an open pull request (gh pr list, the exact commit gh reports, fetched when it is not local) or on a
# branch checked out in a worktree whose last commit is at most <days> old (default 14). Every other branch is ignored
# (stale prototype branches "change" most done/ folders). Prints `<item id> <reason>` per held item, sorted, and a
# final `held: <n>` line.
set -uo pipefail
repo=${1:?usage: held.sh <repo> [<days>]}
days=${2:-14}
cd "$repo" || exit 2
die() { echo "held.sh: $*" >&2; exit 2; }
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
: >"$tmp/out"
git fetch -q origin main || die "cannot fetch origin main"
# (a) active/ on origin/main, not on this checkout (an item readied since the last merge counts)
git ls-tree -r -d --name-only origin/main >"$tmp/dirs" || die "cannot list origin/main"
sed -n -E 's|^.*/\.tracker/(issues\|rafts)/active/([A-Za-z]+[0-9]+)$|\2 active|p' "$tmp/dirs" >>"$tmp/out"
# (b) open pull request heads, at the commit gh reports
command -v gh >/dev/null 2>&1 || die "gh is not installed: open pull requests cannot be read"
gh pr list --state open --limit 500 --json headRefName,headRefOid -q '.[] | "\(.headRefName) \(.headRefOid)"' >"$tmp/prs" 2>"$tmp/gherr" ||
  die "gh pr list failed: $(head -c 300 "$tmp/gherr")"
own=$(git symbolic-ref -q --short HEAD || true) # the raft's own branch and pull request hold nothing
refs=()
while read -r name oid; do
  [[ -n $name ]] || continue
  if ! git cat-file -e "$oid^{commit}" 2>/dev/null; then
    git fetch -q origin "$name" 2>/dev/null || die "cannot fetch the head of the open PR $name"
    git cat-file -e "$oid^{commit}" 2>/dev/null || die "the head $oid of the open PR $name is not local after a fetch"
  fi
  [[ origin/$name == "origin/$own" ]] && continue # the raft's own pull request holds nothing
  refs+=("$oid:origin/$name")
done <"$tmp/prs"
# worktree branches with a recent commit
cutoff=$(($(date +%s) - days * 86400))
while read -r b; do
  [[ -n $b && $b != "$own" ]] || continue
  t=$(git log -1 --format=%ct "$b" 2>/dev/null || echo 0)
  ((t >= cutoff)) && refs+=("$b:$b")
done < <(git worktree list --porcelain | sed -n 's|^branch refs/heads/||p')
for pair in ${refs[@]+"${refs[@]}"}; do
  rev=${pair%%:*} label=${pair#*:}
  git diff --name-only origin/main..."$rev" -- '*/harvest.md' >"$tmp/changed" 2>/dev/null || die "cannot diff origin/main...$label"
  sed -n -E 's|^.*/([A-Za-z]+[0-9]+)/harvest\.md$|\1 branch '"$label"'|p' "$tmp/changed" >>"$tmp/out"
done
sort -u "$tmp/out" | awk '!seen[$1]++'
echo "held: $(sort -u "$tmp/out" | awk '!seen[$1]++' | wc -l | tr -d ' ')"

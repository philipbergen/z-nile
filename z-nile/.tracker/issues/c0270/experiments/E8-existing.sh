#!/usr/bin/env bash
# E8 (design review 001 F2): run the bullet's searches for every issue `preparing` on origin/main, as a resume of its
# prep would, and classify each hit by the revised rule (Design, Decision 5):
#   yours: the prep's branch (`prep-<slug>`, or the head of the open PR titled `prep <id>`), its PR, and every branch
#     or worktree the prep's own document names (a worktree named after one, `proto-c0283-mut` after `proto-c0283`);
#   history: a branch or PR that merged;
#   read, not counted: a closed PR; a PR that only mentions the id; a branch or worktree that holds no design of the
#     issue (its copy of the issue document has the Design section main's has, and no acceptance/ main lacks);
#   counted (another prep under way): anything else.
# The prep's document is its worktree's copy (`.worktree/prep-<slug>`), else `origin/prep-<slug>`'s, else main's.
# Reads refs, worktrees and GitHub only; writes nothing.
# Run: ./zn run --time 900 -- z-nile/.tracker/issues/c0270/experiments/E8-existing.sh
set -uo pipefail
top="$(git rev-parse --show-toplevel)"
cd "$top" || exit 1
main="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"
repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
wts="$(git worktree list --porcelain | awk '/^worktree /{w=$2} /^branch /{b=$2; sub("refs/heads/","",b); print w" "b} /^detached/{print w" (detached)"}')"
ids=$(./zn status | awk '$2=="preparing"{print $1}' | grep -E '^[cdf][0-9]{4}$')
echo "preparing issues: $(wc -w <<<"$ids" | tr -d ' ') ($(date '+%Y-%m-%d %H:%M %Z'))"
design() { awk '/^## Design/{f=1} f&&/^## / && !/^## Design/{exit} f' ; }
for id in $ids; do
  path=$(git grep -l -E "^id: $id$" origin/main -- '*/.tracker/issues/*.md' 2>/dev/null | head -1 | sed 's#^origin/main:##')
  [[ -n $path ]] || { echo "$id: no document on origin/main"; continue; }
  dir=${path%/*}
  slug=$(git show "origin/main:$path" | awk -F': ' '$1=="slug"{print $2; exit}')
  mine="prep-$slug"
  prs=$(gh pr list --repo "$repo" --state all --search "$id" --limit 100 --json number,state,headRefName,title -q '.[]|[.number,.state,.headRefName,.title]|@tsv')
  own=$(awk -F'\t' -v t="prep $id" '$2=="OPEN" && index($4,t){print $3}' <<<"$prs")
  if [[ -f $main/.worktree/$mine/$path ]]; then doc=$(cat "$main/.worktree/$mine/$path")
  elif git rev-parse -q --verify "origin/$mine" >/dev/null; then doc=$(git show "origin/$mine:$path" 2>/dev/null)
  else doc=$(git show "origin/main:$path"); fi
  maindesign=$(git show "origin/main:$path" | design)
  mainacc=$(git ls-tree -r --name-only origin/main -- "$dir/acceptance" | wc -l | tr -d ' ')
  yours() { [[ $1 == "$mine" || ( -n $own && $1 == "$own" ) ]] && return 0; grep -qF -- "$1" <<<"$doc"; }
  # holds a design of the issue: <kind> <ref-or-dir>
  holds() {
    local d a
    if [[ $1 == ref ]]; then d=$(git show "$2:$path" 2>/dev/null | design); a=$(git ls-tree -r --name-only "$2" -- "$dir/acceptance" 2>/dev/null | wc -l | tr -d ' ')
    else d=$(design <"$2/$path" 2>/dev/null); a=$(ls "$2/$dir/acceptance" 2>/dev/null | wc -l | tr -d ' '); fi
    [[ -n $d && $d != "$maindesign" ]] || ((a > mainacc))
  }
  out=()
  while read -r b; do
    [[ -z $b ]] && continue
    b=${b#origin/}
    yours "$b" && continue
    st=$(awk -F'\t' -v h="$b" '$3==h{print $2}' <<<"$prs" | sort -u | tr '\n' ',' | sed 's/,$//')
    [[ $st == *MERGED* ]] && continue
    [[ $st == CLOSED ]] && { out+=("read:branch $b (closed PR)"); continue; }
    holds ref "origin/$b" || { out+=("read:branch $b (no design)"); continue; }
    out+=("branch $b${st:+ ($st)}")
  done < <(git branch -r --list "*$id*" "*$slug*" | sed 's/^ *//')
  while read -r w br; do
    [[ -z $w || $w == "$main" ]] && continue
    n=${w##*/}
    grep -qe "$id" -e "$slug" <<<"$n $br" || continue
    y=0
    for x in "$n" "$br"; do [[ $x == "(detached)" ]] && continue; yours "$x" && y=1; done
    if ((y == 0)); then for p in $(grep -oE "\b(prep|proto)[A-Za-z0-9-]*[A-Za-z0-9]" <<<"$doc" | sort -u); do [[ $n == "$p"* ]] && y=1; done; fi
    ((y)) && continue
    holds dir "$w" || { out+=("read:worktree $n (no design)"); continue; }
    out+=("worktree $n ($br)")
  done <<<"$wts"
  while IFS=$'\t' read -r num st head title; do
    [[ -z $num ]] && continue
    yours "$head" && continue
    [[ $st == MERGED ]] && continue
    if [[ $title == *"prep $id"* ]] || git branch -r --list "*$id*" "*$slug*" | grep -qF -- "origin/$head"; then
      if [[ $st == OPEN ]]; then out+=("PR #$num $head"); else out+=("read:PR #$num $head (closed)"); fi
    else
      out+=("read:PR #$num $head ($st, only mentions $id)")
    fi
  done <<<"$prs"
  counted=$(printf '%s\n' ${out[@]+"${out[@]}"} | grep -v '^read:' | grep -c . || true)
  if ((${#out[@]} == 0)); then echo "$id: none"; else echo "$id: $counted counted: $(printf '%s; ' "${out[@]}")"; fi
done

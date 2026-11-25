#!/usr/bin/env bash
# f0421 S1b's rollout gate (design-review-003 F7). Read-only: it fetches nothing and writes nothing.
# Prints every worktree HEAD and every open pull request head that holds the last commit on main that changed .models.toml
# (so its engine reads today's root) and lacks the gate commit (so its engine would refuse the seed). S1b merges when it
# prints only its header and footer. Run after `git fetch origin`:
#   ./zn run --time 170 -- bash z-nile/.tracker/issues/f0421/rollout-gate.sh [<gate commit>]
set -u
GATE=${1:-5cee0dc8b} # S1a's commit on main (#793); never a branch commit
cd "$(git rev-parse --show-toplevel)" || exit 2
LAST=$(git log -1 --format=%h origin/main -- .models.toml)
echo "gate commit $GATE; last change of .models.toml on main: $LAST ($(git log -1 --format='%cs %s' "$LAST" | cut -c1-70))"
named=0
# every worktree, by its HEAD (detached ones included)
while read -r w h; do
	if git merge-base --is-ancestor "$LAST" "$h" 2>/dev/null && ! git merge-base --is-ancestor "$GATE" "$h" 2>/dev/null; then
		b=$(git -C "$w" branch --show-current 2>/dev/null)
		echo "worktree ${w#"$PWD"/} (${b:-detached at ${h:0:9}})"
		named=$((named + 1))
	fi
done < <(git worktree list --porcelain | awk '/^worktree /{w=$2} /^HEAD /{print w" "$2}')
# every open pull request head
while read -r num ref; do
	[ -n "$num" ] || continue
	h=$(git rev-parse -q --verify "refs/remotes/origin/$ref") || {
		echo "pull request #$num $ref: no origin/$ref here (fetch it)"
		named=$((named + 1))
		continue
	}
	if git merge-base --is-ancestor "$LAST" "$h" && ! git merge-base --is-ancestor "$GATE" "$h"; then
		echo "pull request #$num $ref"
		named=$((named + 1))
	fi
done < <(gh pr list --state open --limit 500 --json number,headRefName -q '.[] | "\(.number) \(.headRefName)"')
echo "$named named: each merges main first (a merged branch's worktree is removed instead)"

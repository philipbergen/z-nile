#!/usr/bin/env bash
# f0421 S1b's rollout gate (design-review-003 F7, review-007 F2). Read-only: it fetches nothing and writes nothing.
# Names every worktree HEAD and every open pull request head whose own z-nile/engine/models.luau reads today's root (its
# text holds TODAY, the review-table parser) and not the new one (its text lacks MARK, the text of the parser the new root
# needs). It decides by each head's own engine, never by ancestry: a branch whose commits main holds as a squash holds the
# code and not the commit (review-007 F2). A head with no z-nile/engine/models.luau is not an engine and is not named. The
# open pull requests are read first: when `gh pr list` fails the script names nothing and exits 3. When origin/main's own
# engine does not hold TODAY (a mistyped second argument, or a later gate's), it names nothing and exits 2 (review-008 F2).
# It exits 1 when it names a head and 0 only when it names none: S1b merges on exit 0. Run after `git fetch origin`:
#   ./zn run --time 170 -- bash z-nile/.tracker/issues/f0421/rollout-gate.sh MARK [TODAY]
# MARK is the text of the parser the new root needs; S1b's is `layer.catalog` (S1a's catalog reader, 5cee0dc8b). A later
# gate (the removal of MODEL_OF_CLI, question 7's edit, an `offers` line for a declared-only CLI) passes the mark of the
# code it waits for.
set -u
MARK=${1:?usage: rollout-gate.sh MARK [TODAY] (S1b: layer.catalog)}
TODAY=${2:-review is a table of aliases}
ENGINE=z-nile/engine/models.luau
cd "$(git rev-parse --show-toplevel)" || exit 2
MAIN=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
if ! git grep -q -F -e "$TODAY" origin/main -- "$ENGINE"; then
	echo "rollout-gate: origin/main's $ENGINE does not hold '$TODAY', so no head can be told to read today's root" >&2
	exit 2
fi
if ! prs=$(gh pr list --state open --limit 500 --json number,headRefName -q '.[] | "\(.number) \(.headRefName)"'); then
	echo "rollout-gate: gh pr list failed: the open pull requests are unknown, so nothing is named" >&2
	exit 3
fi
echo "names each head whose $ENGINE holds '$TODAY' and lacks '$MARK'"
named=0
heads=0
# 0 when the engine at commit $1 reads today's root and not the new one
stale() {
	git cat-file -e "$1:$ENGINE" 2>/dev/null || return 1
	git grep -q -F -e "$TODAY" "$1" -- "$ENGINE" || return 1
	! git grep -q -F -e "$MARK" "$1" -- "$ENGINE"
}
# every worktree, by its HEAD (detached ones included)
while read -r w h; do
	heads=$((heads + 1))
	if stale "$h"; then
		b=$(git -C "$w" branch --show-current 2>/dev/null)
		echo "worktree ${w#"$MAIN"/} (${b:-detached} at ${h:0:9}, last commit $(git log -1 --format=%cs "$h"))"
		named=$((named + 1))
	fi
done < <(git worktree list --porcelain | awk '/^worktree /{w=$2} /^HEAD /{print w" "$2}')
# every open pull request head
while read -r num ref; do
	[ -n "$num" ] || continue
	heads=$((heads + 1))
	h=$(git rev-parse -q --verify "refs/remotes/origin/$ref") || {
		echo "pull request #$num $ref: no origin/$ref here (fetch it)"
		named=$((named + 1))
		continue
	}
	if stale "$h"; then
		echo "pull request #$num $ref (${h:0:9})"
		named=$((named + 1))
	fi
done <<<"$prs"
echo "$named named of $heads heads: each merges main first (a merged branch's worktree is removed instead)"
[ "$named" -eq 0 ]

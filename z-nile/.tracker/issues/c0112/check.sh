#!/usr/bin/env bash
# Acceptance checks for c0112. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0112 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0112"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# The promoted specs pin the rules that stay true (and the docs sentences, once each); what holds only for the backfill
# itself (no source lost, no review edited or deleted, the counts of the day) lives here, where it runs at done and never again.

# The one base AC3 and AC6 judge against (design review 003 F1): origin's main tip as `git ls-remote origin` reads it, never
# the local refs/remotes/origin/main, which one update-ref forges; red when origin can't be read or its tip isn't a local
# commit. BASE is the merge base of HEAD with that tip; HEAD == BASE means the branch has landed (or has no commit yet).
# The URL read is printed: a swapped origin is review's to catch (detect, not prevent).
base_of_main() {
	local url tip
	url=$(git -C "$ZN_ROOT" ls-remote --get-url origin) || return 1
	tip=$(git -C "$ZN_ROOT" ls-remote origin refs/heads/main | cut -f1)
	[[ -n $tip ]] || { echo "git ls-remote origin refs/heads/main read nothing ($url)"; return 1; }
	git -C "$ZN_ROOT" cat-file -e "$tip^{commit}" 2>/dev/null || { echo "origin's main $tip is not a local commit (git fetch origin main)"; return 1; }
	BASE=$(git -C "$ZN_ROOT" merge-base HEAD "$tip") || { echo "no merge base of HEAD and $tip"; return 1; }
	echo "origin $url main $tip, merge base $BASE"
}

check "AC1: on this tree lessons --check, --uncovered and --unattributed print nothing (every finding of every design, code and stream review has an entry, every entry and note names its step), and the same three lists name what is missing on a hand-made tree" \
	lune run tests/run -- "$A/coverage.spec.luau"
ac2() {
	lune run tests/run -- "$A/corpus.spec.luau" || return 1
	# no review was deleted: the corpus of 2026-11-01 (1937 findings, 40 in stream reviews) is a floor that only grows
	local files total stream
	files=$(git -C "$ZN_ROOT" ls-files -- '*/design-review-[0-9]*.md' '*/review-[0-9]*.md' '*/stream-review-*.md' '*/focused-review-[0-9]*.md' ':!*/experiments/*') || return 1
	total=$(printf '%s\n' "$files" | sed "s|^|$ZN_ROOT/|" | tr '\n' '\0' | xargs -0 cat | grep -c '^### F')
	stream=$(printf '%s\n' "$files" | grep '/stream-review-' | sed "s|^|$ZN_ROOT/|" | tr '\n' '\0' | xargs -0 cat | grep -c '^### F')
	((total >= 1937)) || { echo "only $total review findings are tracked (1937 on 2026-11-01)"; return 1; }
	((stream >= 40)) || { echo "only $stream stream review findings are tracked (40 on 2026-11-01)"; return 1; }
}
check "AC2: the coverage reader finds every review kind and every finding has an entry, no two lessons share a title or a check question, and the review corpus of 2026-11-01 (1937 findings, 40 of them in stream reviews) is still tracked" ac2
ac3() {
	# every lesson main had when this branch last merged it, and every source of it, is still here: sets, compared by the
	# branch's own engine (acceptance/sources-kept.luau, sequestered with this file) on a copy of the merge base made with
	# git archive in a temporary folder outside the repository. What main gained later is main's, not this branch's.
	local tmp rc BASE
	lune run tests/run -- "$A/sources-kept.spec.luau" || return 1 # both modes of the script, on small trees
	base_of_main || return 1
	if [[ $BASE == "$(git -C "$ZN_ROOT" rev-parse HEAD)" ]]; then
		echo "HEAD is on origin's main (landed, or no commit yet): nothing to compare"
		return 0
	fi
	tmp=$(mktemp -d) || return 1
	git -C "$ZN_ROOT" archive "$BASE" | tar -x -C "$tmp" || { rm -rf "$tmp"; return 1; }
	lune run "$A/sources-kept.luau" -- "$tmp" "$ZN_ROOT"
	rc=$?
	rm -rf "$tmp"
	return $rc
}
check "AC3: sources-kept.spec passes (both modes of the script, on small trees), and no lesson of the merge base with origin/main (157 on 2026-11-01) is gone and no source it has is lost, compared as sets (a lesson id may move to a note headed for its finding; a note may be reworded only by the fixed function in sources-kept.luau)" ac3
check "AC4: R0039's harvest has one design-first-pass-checklist note per point 1 to 12, each naming a design lesson that one of R0039's own findings is also a source of" \
	lune run tests/run -- "$A/seeds.spec.luau"
check "AC5: a grouped note may name an issue id (f0110), and a word shaped like a finding still marks a mistyped head" \
	lune run tests/run -- "$A/note-ids.spec.luau"
ac6() {
	lune run tests/run -- "$A/docs.spec.luau" || return 1
	# a review or refute that main has is history: this branch deletes, edits, renames or retypes none. It may add its
	# own (the code review and refute of its raft, stream reviews): an addition only adds findings to harvest.
	local changed BASE
	base_of_main || return 1
	changed=$(git -C "$ZN_ROOT" diff --name-status --diff-filter=DMRT "$BASE" HEAD -- '*design-review-*.md' '*/review-[0-9]*.md' '*stream-review-*.md' '*/focused-review-[0-9]*.md' '*refute-*.md' ':!*/experiments/*') || return 1
	[[ -z $changed ]] || { echo "review or refute files changed:"; echo "$changed"; return 1; }
}
check "AC6: the skills and AGENTS.md say the full gate enforces coverage and what a harvest.md conflict does, and no review or refute that origin/main has is deleted, edited, renamed or retyped (the raft's own code review and refute are added)" ac6

finish

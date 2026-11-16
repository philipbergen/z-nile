#!/usr/bin/env bash
# Acceptance checks for c0300. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0300 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0300"

# layercommits.spec is pure (well under a second). restack-keeps.spec drives real git in one fixture under .cache
# (a local bare origin, a gh stub) and its cases build on each other, so it runs once (AC1; 57-104 s measured on a
# machine at load average ~40) and each
# criterion then checks that every one of its own cases passed: the runner writes each passing case's name to $OUT.
OUT="$PWD/.cache/c0300-check/restack-keeps.txt"
keeps() {
	local home rel
	home="$(pwd -P)"
	rel="${A#"$home"/}/restack-keeps.spec.luau" # the runner takes the spec's path from the project home
	if [[ ${1:-} == --run ]]; then
		shift
		mkdir -p "${OUT%/*}" && : >"$OUT" # an empty record when no case passes: each criterion then names the case that did not
		# the runner reads the project registry from the repository root
		(cd "$(git rev-parse --show-toplevel)" && lune run "$home/specs" -- run --project z-nile --out "$OUT" -- "$rel") || true
	fi
	[[ -f $OUT ]] || { echo "restack-keeps.spec did not run"; return 1; }
	local c
	for c in "$@"; do
		grep -qxF "	$c" "$OUT" || { echo "did not pass: $c"; return 1; }
	done
}
SETUP='sets up a readied raft whose layer holds four worker commits'
FINISH='AC1, AC4: finish names restack, restack keeps every commit (an unpushed one too), and finish then succeeds'
# the restated rule in the usage text, the stack contract comment and zz-rules
rules() {
	local top
	top="$(git rev-parse --show-toplevel)"
	grep -qF 'restack <R-id>                                rebase each layer onto the one below, keeping every commit; stop at the first conflict, lost commit or red check' "$top/z-nile/engine/main.luau" || { echo "usage line"; return 1; }
	grep -qF 'Every one of them is kept, with its subject and change, or the layer is refused unchanged.' "$top/z-nile/engine/stack.luau" || { echo "stack.luau contract"; return 1; }
	grep -qF 'A restack keeps every commit of each layer, or refuses that layer and leaves it as it was.' "$top/z-nile/skills/zz-rules/SKILL.md" || { echo "zz-rules sentence"; return 1; }
}

pure() { lune run tests/run -- "$A/layercommits.spec.luau"; }
ac1() { keeps --run "$SETUP" "$FINISH" && pure; }
ac2() {
	keeps 'AC2: a conflict refuses the layer with its branch, its remote and the worktree as they were' \
		'AC2: a commit whose change is already on main refuses the layer unchanged and says what to do' \
		'AC2: a local branch and origin copy that have diverged refuse the layer unchanged' && pure
}

check "AC1: a restack of an unfinished layer keeps one commit for each commit it held (its unpushed ones too), same subject, same change, same order, on the new main, and pushes that" ac1
check "AC2: a layer whose rebase conflicts, whose commit would lose its change, or whose local and origin copies diverged, is refused with its branch and remote unchanged, and the refusal says what to do" ac2
ac3() {
	keeps 'AC3: a restack whose rebuilt layer fails its check leaves the branch and its remote where they were' \
		'AC3: a restack killed during its check leaves no ref on a layer missing a commit' \
		'AC3: the restack after a killed one finishes the layer, with no hand repair' \
		'AC3: a restack killed when main does not move again is finished by the next one, which pushes it' && pure
}
check "AC3: a restack whose check is red, or that is killed during its check, leaves neither the layer branch nor its remote on a commit set missing a commit, and the next restack finishes the layer with no hand repair" ac3
check "AC4: finish on a layer only behind main names ./zn restack, which moves the layer onto main with no hand rebase, and finish then succeeds" keeps "$FINISH"
check "AC5: the usage text, the stack contract comment and zz-rules state the rule" rules

finish

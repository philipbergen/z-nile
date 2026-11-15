#!/usr/bin/env bash
# Acceptance checks for c0325. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0325 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0325"

# match.spec is a plain spec (pure: in-memory .models.toml layers, no fixture repository). It runs once, and every
# criterion then checks that each of its own cases passed: the runner writes each passing case's name to the --out
# file, but only when the whole run passes (z-nile/specs.luau), so one red case leaves the record empty and every
# criterion reports it (lesson zz-test/out-records-only-a-green-run): read the run's FAIL lines.
OUT="$PWD/.cache/c0325-check"
fixtureSpec() {
	local file="$1" home rel out
	shift
	home="$(pwd -P)"
	rel="${A#"$home"/}/$file.spec.luau" # the runner takes the spec's path from the project home
	out="$OUT/$file.txt"
	if [[ ${1:-} == --run ]]; then
		shift
		mkdir -p "$OUT" && : >"$out" # an empty record when no case passes: each criterion then names the case that did not
		# the runner reads the project registry from the repository root
		(cd "$(git rev-parse --show-toplevel)" && lune run "$home/specs" -- run --project z-nile --out "$out" -- "$rel") || true
	fi
	[[ -f $out ]] || { echo "$file.spec did not run"; return 1; }
	local c
	for c in "$@"; do
		grep -qxF "	$c" "$out" || { echo "did not pass: $c (or another case of $file.spec failed: the record is written only for a green run, so read its FAIL lines)"; return 1; }
	done
}

# the fast specs this change touches: of the Design's Affected specs, those not in the measured slow tier
# (tests/slow.tsv). The slow tier is the gate's (z-nile/check.sh --slow), never this check.sh's.
fastSpecs() {
	local s
	for s in tests/acceptance/c0117/adapters.spec.luau tests/acceptance/c0117/control-cli.spec.luau tests/acceptance/c0117/dispatch-cli.spec.luau tests/acceptance/c0117/dispatch.spec.luau tests/acceptance/c0117/docs.spec.luau tests/acceptance/c0117/ledger.spec.luau tests/acceptance/c0117/models.spec.luau tests/acceptance/c0117/trackerstate.spec.luau tests/acceptance/c0117/wrapper.spec.luau tests/tooling/dispatch-guards.spec.luau tests/tooling/dispatch-texts.spec.luau tests/tooling/idea.spec.luau tests/tooling/raftcheck.spec.luau tests/tooling/roles.spec.luau tests/tooling/wrapper-guards.spec.luau; do
		grep -qF "	$s" tests/slow.tsv || printf '%s\n' "$s"
	done
}
runFast() {
	local list
	list=$(fastSpecs)
	[[ -n $list ]] || { echo "no fast spec is listed"; return 1; }
	# shellcheck disable=SC2086 # one spec path per word
	lune run tests/run -- $list
}

ac1() {
	fixtureSpec match --run "AC1: a spend row of the author's primary try matches the same model at any effort" "AC1: a spend row of a fallback try matches that fallback's model at any effort" "AC1: a spend row whose effort has a hyphen is cut by the author's tries, not at the last hyphen" "AC1: a bare typed id matches the same model at another effort" "AC1: a model whose id only starts with the author's model is not the author's"
}
check "AC1: \`models.isAuthor\` is true for a challenger try running the model that wrote the text, whether the record is a spend row's \`<model>-<effort>\` of any author try (the primary or a fallback) or a bare typed or stamped id, at any effort on either side, and false for another model, including one whose id only starts with the author's model (\`kimi-code-k3.1\` against \`kimi-code-k3.1-pro-high\`)." ac1
ac2() {
	fixtureSpec match "AC2: with no record the first choice of the author role is compared, effort ignored" "AC2: a role with no author never matches, with a record or without" "AC2: Resolved.author is set exactly where authorModel is, which keeps its value"
}
check "AC2: with no record, \`models.isAuthor\` compares with the author role's first choice, its effort ignored; a role with no author is never matched; \`resolveRole\` sets \`Resolved.author\` exactly where it sets \`authorModel\`, which keeps its value." ac2
ac3() {
	fixtureSpec match "AC3: a bare record loses one trailing context marker" "AC3: a record that is an author try's id is cut to that try's model and keeps its marker"
}
check "AC3: \`models.modelOf\` removes one trailing \`[...]\` context marker from a bare record (\`claude-opus-5-5[1m]\` is \`claude-opus-5-5\`), and never from a record it recognised as an author try." ac3
ac4() {
	fixtureSpec match "AC4: tries keeps a fallback author, and keeps the same model at another effort" "AC4: tries still stops when the only model left is the author's, and not at another effort"
}
check "AC4: \`models.tries\` returns the same tries, or the same error, for every input as before, including a fallback author it still keeps and the same model at another effort." ac4
check "AC5: the fast specs this change touches still pass, those of them not in \`tests/slow.tsv\` when it runs (the slow tier is the gate's)." runFast

finish

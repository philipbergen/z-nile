#!/usr/bin/env bash
# Acceptance checks for c0183. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0183 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0183"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# The exact claims about the delivered tree live here, where they run at done and never again; the promoted specs
# pin the rules (design review 001 F1, F3).

SEVEN=$'pickman\tpickman\tpickman/.tracker\nz-nile\tz-nile\tz-nile/.tracker\narcade\tarcade\tarcade/.tracker\nportal\tportal\tportal/.tracker\nsnake\tsnake\tsnake/.tracker\ninvaders\tinvaders\tinvaders/.tracker\nasteroids\tasteroids\tasteroids/.tracker'
check "AC1: the registry lists pickman, z-nile, arcade, portal, snake, invaders and asteroids, in that order" \
	bash -c 'lune run tests/run -- "$1" && got=$(cd "$ZN_ROOT" && lune run "$PWD/z-nile/roots" -- --projects) &&
		{ [[ $got == "$2" ]] || { printf "roots --projects printed:\n%s\n" "$got"; exit 1; }; }' \
	ac1 "$A/registry.spec.luau" "$SEVEN"
check "AC2: every new project lists its items, and the tracker audit finds no error with the new roots" \
	bash -c 'for n in arcade portal snake invaders asteroids; do
		"$ZN_ROOT/zn" list --project "$n" >/dev/null || { echo "no project $n"; exit 1; }
	done && "$ZN_ROOT/zn" audit'
# the nine files' digests, from experiments/E4-digests.py over c0183.md (the same digests designs.spec pins)
DIGESTS='6b8d831adc1fac1772b34037efbafdceb519e727394719645c8a1de4b111307c  snake/.tracker/game-design.md
512c8d085d2dbf35702e43d5e1b78289e2efae4c91f373f9f09e6b525f82a71d  invaders/.tracker/game-design.md
12e8c3351f9427a23fed5b98cef338c68a2bce6ee3a75e815200018995aac3b5  asteroids/.tracker/game-design.md
5007ca3d719277ebfc75b4e62db9738a1701f08be8836831f4fc9f63ffe4e718  portal/.tracker/game-design.md
01cc48774876255c5a46fcc8f5e59dbf5b5f4ccd04a250849bdeb432e6bd1f10  arcade/.tracker/architecture.md
3d5b251bfed0b8796c4e6c5701b34e7f0f4129f25900f9c0de5b9d5812623db6  portal/.tracker/architecture.md
4450e243e036f6687ff7d0b260949f00b2a61d6938a3a1186fcd3e7d2ffb69ca  snake/.tracker/architecture.md
7486a2368eafdf281bda75e26afec789c5e7c0a2c0ca52f697ef31c3173b3407  invaders/.tracker/architecture.md
7c325cfebe4a1f54b21dc7b38f8bef1b926afb09cca9f1c0b083ed434f05ddb5  asteroids/.tracker/architecture.md'
check "AC3: the delivered designs and stub maps are exactly the moved blocks and stubs, and the promoted rule holds" \
	bash -c 'lune run tests/run -- "$1" && cd "$ZN_ROOT" && printf "%s\n" "$2" | shasum -a 256 -c --quiet -' \
	ac3 "$A/designs.spec.luau" "$DIGESTS"
check "AC4: the gate's plan type-checks each new home and runs no specs or builds there" \
	bash -c 'p=$(./check.sh --full --plan) && for n in arcade portal snake invaders asteroids; do
		printf "%s\n" "$p" | grep -qE "^types \(Lune\): (.* )?$n( |\$)" || { echo "no Lune types for $n"; exit 1; }
		if printf "%s\n" "$p" | grep -qE "^(specs: $n,|build: $n/)"; then echo "specs or a build for $n"; exit 1; fi
	done'
check "AC5: a new project takes captures in its own root, and lists its own items" \
	lune run tests/run -- "$A/capture.spec.luau"
# The exact sentences are grep patterns written inline: the path scanners (c0120's check-paths and finished.spec, and
# c0141's) skip a grep's pattern, but read a variable's words as paths (design review 003 F1). No pattern starts with
# "(", which they would not skip.
ac6() {
	lune run tests/run -- "$A/docs.spec.luau" &&
		grep -qF -- "The arcade's projects are registered too (c0183): \`arcade/\` (the library every place shares), \`portal/\` (the experience's start place) and the games \`snake/\`, \`invaders/\` and \`asteroids/\`; each keeps its product decisions in \`<name>/.tracker/game-design.md\`, and the library its design in \`arcade/.tracker/architecture.md\`." "$ZN_ROOT/AGENTS.md" &&
		grep -qF -- "The arcade adds five more (c0183): the shared library \`arcade\`, the start place \`portal\`, and the games \`snake\`, \`invaders\` and \`asteroids\`, each in its own folder." "$ZN_ROOT/z-nile/README.md" &&
		grep -qF -- "the work of a game, the portal or the arcade library is its project's (\`--project pickman\`, \`--project snake\`, \`--project portal\`, \`--project arcade\`, …: a name in \`z-nile/projects.toml\`), or a capture run in that project's folder (\`pickman/\`, \`snake/\`, …) (zz-rules skill, Projects)" "$ZN_ROOT/z-nile/skills/z-ticket/SKILL.md" &&
		grep -qF -- "There, the work of a game, the portal or the arcade library passes its project (\`--project pickman\`, \`--project snake\`, \`--project portal\`, \`--project arcade\`, …: a name in \`z-nile/projects.toml\`) and tooling (the tracker, the gate, the guards, the skills) \`--project z-nile\`." "$ZN_ROOT/z-nile/skills/zz-rules/SKILL.md" &&
		grep -qF -- "The arcade's projects keep theirs the same way, \`<name>/.tracker/\` with the home \`<name>/\` (c0183: \`arcade\`, \`portal\`, \`snake\`, \`invaders\`, \`asteroids\`)." "$ZN_ROOT/z-nile/skills/zz-rules/SKILL.md" &&
		grep -qF -- "\`<root>\` is the item's project root, \`<name>/.tracker\` for a project of \`z-nile/projects.toml\`, such as \`pickman/.tracker\` or \`z-nile/.tracker\`" "$ZN_ROOT/z-nile/skills/zz-rules/SKILL.md"
}
check "AC6: AGENTS.md, the README and the z-ticket and zz-rules skills carry the exact sentences that name the projects" ac6

finish

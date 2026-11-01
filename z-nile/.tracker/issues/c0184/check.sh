#!/usr/bin/env bash
# Acceptance checks for c0184. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0184 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0184"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# The exact claims about the delivered tree live here, where they run at done and never again; the promoted specs pin
# the rules (zz-test lesson promoted-specs-pin-rules-not-sets). The checkout's paths are named through $ZN_ROOT and
# the homes through a loop variable, which the path scanners read as no path (zz-test lesson
# sentences-in-checks-are-grep-patterns).

FIVE="arcade portal snake invaders asteroids"
check "AC1: pickman and the arcade's five projects have the home scaffold, and a project the registry adds later is held to it" \
	bash -c 'lune run tests/run -- "$1" && for n in $2; do
		"$ZN_ROOT/zn" list --project "$n" >/dev/null || { echo "no project $n"; exit 1; }
		[[ -f $ZN_ROOT/$n/default.project.json ]] || { echo "no home for $n"; exit 1; }
	done && lune run "$3/experiments/places.luau" "$ZN_ROOT"' ac1 "$A/homes.spec.luau" "$FIVE" "$HERE"
check "AC2: the gate plans each of the five homes: Roblox types for its src, a build of its place, and its specs from its home" \
	bash -c 'p=$(./check.sh --full --plan) && for n in $1; do
		printf "%s\n" "$p" | grep -qxF "types (Roblox): $n/src, from $n" || { echo "no Roblox types for $n"; exit 1; }
		printf "%s\n" "$p" | grep -qxF "build: $n/default.project.json" || { echo "no build for $n"; exit 1; }
		printf "%s\n" "$p" | grep -qxF "specs: $n, from $n" || { echo "no specs for $n"; exit 1; }
		printf "%s\n" "$p" | grep -qE "^types \(Lune\): (.* )?$n/tests( |\$)" || { echo "no Lune types for $n/tests"; exit 1; }
	done' ac2 "$FIVE"
check "AC3: each of the five homes passes its own gate, run alone from its own check.sh" \
	bash -c 'for n in $1; do
		bash "$ZN_ROOT/$n/check.sh" --full || { echo "the gate of $n failed"; exit 1; }
	done' ac3 "$FIVE"
check "AC4: the stop hook, the reviewed .cache list and the repository-fence scan take every home from the registry" \
	lune run tests/run -- "$A/generic.spec.luau"
check "AC5: the root .luaurc keeps no alias into a game, and the specs that pinned it say so" \
	bash -c '! grep -qE "\"(logic|shared)\"" "$ZN_ROOT/.luaurc" &&
		lune run tests/run -- tests/acceptance/c0120/layout.spec.luau tests/acceptance/c0120/graph-homes.spec.luau'
# The text of the five projects' skills is today's claim, so it is here and not in a promoted spec: each reads pickman's
# rules first and extends them, the library states the leaf rule, the games its other half (grep patterns written inline).
ac6() {
	"$ZN_ROOT/zn" skills --check && lune run tests/run -- "$A/skills.spec.luau" || return 1
	local n
	for n in $FIVE; do
		[[ -L $ZN_ROOT/.claude/skills/$n-arch && -L $ZN_ROOT/.claude/skills/$n-test ]] || { echo "no link for $n"; return 1; }
		grep -qF -- 'Read `pickman/skills/pickman-arch/SKILL.md` first' "$ZN_ROOT/$n/skills/$n-arch/SKILL.md" &&
			grep -qxF -- 'extends: pickman-arch' "$ZN_ROOT/$n/skills/$n-arch/SKILL.md" &&
			grep -qF -- "./zn lessons --skill $n-arch --full" "$ZN_ROOT/$n/skills/$n-arch/SKILL.md" &&
			grep -qF -- '`pickman/skills/pickman-test/SKILL.md`: read it' "$ZN_ROOT/$n/skills/$n-test/SKILL.md" &&
			grep -qxF -- 'extends: pickman-test' "$ZN_ROOT/$n/skills/$n-test/SKILL.md" &&
			grep -qF -- "cd $n && lune run tests/run" "$ZN_ROOT/$n/skills/$n-test/SKILL.md" || { echo "the skills of $n"; return 1; }
		[[ $n == arcade ]] && continue
		grep -qF -- 'never requires arcade Logic' "$ZN_ROOT/$n/skills/$n-arch/SKILL.md" &&
			grep -qF -- '`@game/ReplicatedStorage/Arcade/...`' "$ZN_ROOT/$n/skills/$n-arch/SKILL.md" || { echo "the leaf rule in $n-arch"; return 1; }
	done
	grep -qF -- '**A library feature is a leaf.**' "$ZN_ROOT/arcade/skills/arcade-arch/SKILL.md" &&
		grep -qF -- "A game's Logic never requires library Logic either" "$ZN_ROOT/arcade/skills/arcade-arch/SKILL.md" &&
		grep -qF -- 'ServerStorage.Arcade' "$ZN_ROOT/arcade/skills/arcade-arch/SKILL.md"
}
check "AC6: each of the ten skills is there and linked, extends pickman's, and states the leaf rule" ac6
# the exact rows are written inline as grep patterns (today's five; docs.spec pins the rule for any project)
ac7() {
	lune run tests/run -- "$A/docs.spec.luau" &&
		grep -qF -- '| `<name>/skills/<name>-arch/SKILL.md`, for `arcade`, `portal`, `snake`, `invaders` and `asteroids` |' "$ZN_ROOT/AGENTS.md" &&
		grep -qF -- '| `<name>/skills/<name>-test/SKILL.md`, for the same five |' "$ZN_ROOT/AGENTS.md" &&
		grep -qF -- '| `arcade-arch`, `arcade-test`, `portal-arch`, `portal-test`, `snake-arch`, `snake-test`, `invaders-arch`, `invaders-test`, `asteroids-arch`, `asteroids-test` |' "$ZN_ROOT/z-nile/README.md" &&
		grep -qF -- "The arcade's projects extend this skill (\`extends: pickman-arch\`, c0184): a rule changed here changes theirs, so a change names its effect on them." "$ZN_ROOT/pickman/skills/pickman-arch/SKILL.md" &&
		grep -qF -- "The arcade's projects extend this skill (\`extends: pickman-test\`, c0184): a rule changed here changes theirs, so a change names its effect on them." "$ZN_ROOT/pickman/skills/pickman-test/SKILL.md" &&
		grep -qF -- "with the skills they extend" "$ZN_ROOT/z-nile/templates/prompt.md"
}
check "AC7: AGENTS.md, the README, zz-rules, zz-test, pickman's two skills and the prompt template carry the restated rules" ac7
check "AC8: nothing pickman plays or builds changes: its src and its Rojo projects are the merge base's" \
	bash -c 'base=$(git -C "$ZN_ROOT" merge-base HEAD origin/main) &&
		git -C "$ZN_ROOT" diff --quiet "$base" -- ":(top)$1/src" ":(top)$1/default.project.json" ":(top)$1/lobby.project.json"' ac8 pickman
check "AC9: the specs this chore overrides or touches pass" \
	lune run tests/run -- tests/acceptance/c0114/gate-cover.spec.luau tests/acceptance/c0120/ci.spec.luau \
	tests/acceptance/c0120/docs.spec.luau tests/acceptance/c0115/docs.spec.luau tests/tooling/repo-fence.spec.luau \
	tests/acceptance/c0077/cache-paths.spec.luau tests/acceptance/c0005/worktree.spec.luau \
	tests/acceptance/c0115/skills.spec.luau tests/acceptance/c0115/prompt.spec.luau tests/acceptance/c0115/lessons.spec.luau \
	tests/acceptance/c0115/absence.spec.luau tests/acceptance/c0067/ready.spec.luau tests/acceptance/c0111/prompt-lessons.spec.luau \
	tests/acceptance/c0111/skill-docs.spec.luau tests/acceptance/c0115/readme.spec.luau tests/acceptance/c0006/clone.spec.luau \
	tests/acceptance/c0114/docs.spec.luau tests/acceptance/c0115/layout.spec.luau \
	tests/acceptance/c0172/narrowed.spec.luau

finish

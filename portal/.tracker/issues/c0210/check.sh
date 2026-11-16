#!/usr/bin/env bash
# Acceptance checks for c0210. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home (portal/)
# sequestered specs: here before `./zn done`, promoted to portal/tests/acceptance/c0210 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0210"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: portal/experience.json lists every place of arcade's Places once, each with the variable the architecture names (Pickman's new one, then ROBLOX_BETA_GAME_PLACE_ID), its own home's default project, Pickman's outputs and LobbyPlaceId kept; its one reader refuses every ambiguous or unsafe manifest, naming the rule" \
	lune run tests/run -- "$A/manifest.spec.luau"
check "AC2: the plan: not configured is no plan; a place whose variable is unset or empty is skipped and told 0; the games in the manifest's order, the start place last; every published place told every place id, paid play's test mode with every product id 0, and its build's extra ids; the old variable still Pickman's; bad ids, disagreeing variables and two places with one id refused, naming the variables and never the key" \
	lune run tests/run -- "$A/plan.spec.luau"
check "AC3: deploy-beta over a fixture experience: every place whose variable is set built, then published games first and the start place last, each built place carrying its attributes; an unset place not built; a build failure or a bad id stops every publish; a refused publish names what went out and writes no version; a missing or broken manifest fails; not configured skips green" \
	lune run tests/run -- "$A/deploy.spec.luau"
check "AC4: until f0209, with the checked-in manifest and the real projects, pickman's game goes to its id told LobbyPlaceId and pickman's lobby to the start place told GamePlaceId, with version and lobby_version as before, and --place Portal and --place Pickman run the lobby's and the game's runtime scripts" \
	lune run tests/run -- "$A/lobby.spec.luau"
check "AC5: runtime-test --place <name>: usage and unknown names exit 2; not configured, an unpublished place and a place with no runtime folder skip green; given files run at that place's id; with none, its build's runtime folder in order; Pickman without --place; a failing script, a bad id or a missing manifest fail" \
	lune run tests/run -- "$A/runtime.spec.luau"
check "AC6: deploy.yml runs lune run scripts/deploy-beta from portal/ with exactly the key, the universe and every variable of the manifest, and still comments Pickman's version" \
	lune run tests/run -- "$A/workflow.spec.luau"
check "AC7: the deploy scripts are in portal/scripts and pickman/scripts keeps only its forwarders; @scripts reaches them from portal and pickman; zz-rules, SETUP.md and pickman-test say portal/ and --place" \
	lune run tests/run -- "$A/layout.spec.luau"
check "AC8: every build of the checked-in manifest builds with the real Rojo from portal/ with every attribute the plan gives it, typed, and the checked-in project files unchanged" \
	lune run tests/run -- "$A/build.spec.luau"
# the Overrides' promoted specs, each from its own home (pickman's and z-nile's), with c0193's loops lint, whose helper
# this issue points at portal/scripts
overrides() {
	local p="$ZN_ROOT/pickman/tests/acceptance" z="$ZN_ROOT/z-nile/tests/acceptance"
	(cd "$ZN_ROOT/pickman" && lune run tests/run -- "$p"/c0003/*.spec.luau "$p"/c0015/*.spec.luau "$p"/c0051/*.spec.luau "$p"/c0064/*.spec.luau) || return 1
	(cd "$ZN_ROOT/z-nile" && lune run tests/run -- "$z"/c0120/ci.spec.luau "$z"/c0120/layout.spec.luau "$z"/c0120/docs.spec.luau "$z"/c0172/*.spec.luau "$z"/c0193/tree.spec.luau) || return 1
}
check "AC9: the deploy area's promoted specs, as this issue changes them (its Overrides), and c0193's loops lint pass from their homes" overrides

finish

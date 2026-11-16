#!/usr/bin/env bash
# Acceptance checks for f0209. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home (portal/)
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0209 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0209"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: in portal/experience.json the start place (the one place reading ROBLOX_BETA_PLACE_ID, Portal) publishes the portal's own project with its runtime folder and no extra attribute, no place publishes pickman's lobby, and the output keeps its name lobby_version; the plan for the start place and Pickman's game sends the game to its id told the start place's id, then the portal to the start place told Pickman's id and paid play's test mode, with no GamePlaceId; every published game is told the portal's id as PortalPlaceId." \
	lune run tests/run -- "$A/start.spec.luau"
check "AC2: deploy-beta with the checked-in manifest and the real projects publishes Pickman's game and then the portal to ROBLOX_BETA_PLACE_ID, never pickman's lobby: the start place holds the portal's own server and no lobby, told Pickman's and its own id; the game is told the start place's id; the outputs are version and lobby_version; no variable from the caller's shell reaches it." \
	lune run tests/run -- "$A/deploy.spec.luau"
check "AC3: portal/tests/runtime holds a structure check that passes in the portal the deploy publishes at the start place and fails in an untold portal, in pickman's lobby and in pickman's game; runtime-test --place Portal runs exactly those scripts at the start place's id." \
	lune run tests/run -- "$A/runtime.spec.luau"
check "AC4: the switch is one line of the manifest, and that line set back publishes pickman's lobby to the start place told GamePlaceId, as before f0209." \
	lune run tests/run -- "$A/rollback.spec.luau"
check "AC5: SETUP.md, pickman's game design, portal-test and pickman-test say the start place is the portal since f0209, how it is rolled back, and that its runtime tests are portal/tests/runtime." \
	lune run tests/run -- "$A/docs.spec.luau"
# the deploy area's promoted specs, from their homes: c0210's (with lobby-start.spec removed by c0392, which would be
# red here otherwise), and the promoted specs c0210 overrides or guards in pickman and z-nile (c0210's AC9 list); c0210
# is done before this issue runs, so its folder is named from the root
deploy_area() {
	local p="$ZN_ROOT/pickman/tests/acceptance" z="$ZN_ROOT/z-nile/tests/acceptance"
	(cd "$ZN_ROOT/portal" && lune run tests/run -- "$ZN_ROOT"/portal/tests/acceptance/c0210/*.spec.luau) || return 1
	(cd "$ZN_ROOT/pickman" && lune run tests/run -- "$p"/c0003/*.spec.luau "$p"/c0015/*.spec.luau "$p"/c0051/*.spec.luau "$p"/c0064/*.spec.luau) || return 1
	(cd "$ZN_ROOT/z-nile" && lune run tests/run -- "$z"/c0120/ci.spec.luau "$z"/c0120/layout.spec.luau "$z"/c0120/docs.spec.luau "$z"/c0172/*.spec.luau "$z"/c0193/tree.spec.luau "$z"/c0194/callers.spec.luau "$z"/c0194/docs.spec.luau) || return 1
}
check "AC6: c0210's promoted specs (lobby-start.spec removed by c0392) and the deploy area's promoted specs in pickman and z-nile pass from their homes." deploy_area

finish

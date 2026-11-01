#!/usr/bin/env bash
# Acceptance checks for c0190. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0190 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0190"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# The promoted spec pins what a later prep keeps (each issue, its type, its implied dependencies, its Problem's quote
# and pointer), found by slug. AC4 holds the claim about history, which runs at done and never again: `./zn capture`
# reads origin/main, which a gate clone has no copy of.
check "AC1: each listed issue exists once in its project, with its type" lune run tests/run -- "$A/captured.spec.luau"
check "AC2: each issue's depends_on holds the issues the list implies" lune run tests/run -- "$A/captured.spec.luau"
check "AC3: each Problem quotes the user and points at its design" lune run tests/run -- "$A/captured.spec.luau"
# project:slug of every listed issue, in the list's order
PAIRS="arcade:hiscores-with-revives pickman:switch-to-arcade-hiscores arcade:shared-travel pickman:switch-to-arcade-travel arcade:paid-play-and-receipts pickman:switch-to-arcade-paid-play arcade:input-and-look-cores pickman:switch-to-arcade-input-cores portal:game-carousel portal:boards-per-game portal:free-game-timer portal:play-buttons portal:portal-start-place portal:n-place-deploy snake:arena-maps-growth snake:shared-snake-arena snake:snake-first-person-view snake:boost-golden-apples-crumbs snake:snake-scores-and-revives invaders:invaders-classic-rules invaders:invaders-two-players invaders:invaders-cannon-view invaders:invaders-scores-and-revives asteroids:asteroids-classic-rules asteroids:asteroids-two-players asteroids:asteroids-cockpit-view asteroids:asteroids-scores-and-revives"
# Each issue's capture (`./zn capture`) is the filled document, from a commit whose subject lists the ids, so a prep
# reads the whole captured scope, never the one-line stub (z-ticket lesson capture-subject-lists-every-id).
ac4() {
	local pair p s docs id head body
	for pair in $PAIRS; do
		p=${pair%%:*} s=${pair#*:}
		docs=$(grep -lx -- "slug: $s" "$ZN_ROOT/$p"/.tracker/issues/*/*.md "$ZN_ROOT/$p"/.tracker/issues/*/*/*.md 2>/dev/null)
		[[ -n $docs && $docs != *$'\n'* ]] || { echo "$pair: not exactly one issue"; return 1; }
		id=$(basename "$docs" .md)
		body=$("$ZN_ROOT/zn" capture "$id") || { echo "$pair: zn capture $id failed"; return 1; }
		head=${body%%$'\n'*}
		[[ $head == "capture "*" tracker: new "* && $head != *"(no capture commit"* && $head != *"(ambiguous"* ]] ||
			{ echo "$pair: capture header: $head"; return 1; }
		[[ " ${head#* tracker: new } " == *" $id "* ]] || { echo "$pair: $id not in the subject: $head"; return 1; }
		grep -qF -- '"I want to branch out into multiple games' <<<"$body" || { echo "$pair: the capture of $id is the stub"; return 1; }
	done
}
check "AC4: each issue's capture is its filled document, from a capture commit that lists its id" ac4

finish

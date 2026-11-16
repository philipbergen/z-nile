#!/usr/bin/env bash
# Acceptance checks for c0185. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0185 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0185"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# The exact claims about the delivered tree live here, where they run at done and never again; the promoted specs pin the
# rules (zz-test lesson promoted-specs-pin-rules-not-sets). Other projects' files are named through $ZN_ROOT or a loop
# variable, which the path scanners read as no path (zz-test lesson sentences-in-checks-are-grep-patterns).

SIX="arcade portal snake invaders asteroids pickman"

check "AC1: @game/ServerStorage/ is allowed from a server root only" \
	lune run tests/run -- "$A/graph.spec.luau"
check "AC2: a home's place specs depend on what its project files map, another home's folders included, and every project file forces its project's run" \
	lune run tests/run -- "$A/graph.spec.luau" "$A/selector.spec.luau"
check "AC3: a change under arcade/ selects the place specs of every home that maps the library, and the unit specs that reach it through @arcade" \
	lune run tests/run -- "$A/graph.spec.luau" "$A/selector.spec.luau"

# The six homes' wiring: the alias, the two mappings and the place tier are the rule's (library.spec pins it for any project);
# today's six are named here, with their gates. The five new homes pass their whole gate (small). Pickman's static stages
# (formatting, lint, Roblox types with the library in its sourcemap, both builds) run with no spec selected: its specs are
# the merge's full gate and AC5's and AC8's lists.
ac4() {
	lune run tests/run -- "$A/library.spec.luau" || return 1
	local n lib=../arcade/src
	for n in $SIX; do
		grep -qF -- "\"arcade\": \"$lib/shared\"" "$ZN_ROOT/$n/.luaurc" || { echo "no arcade alias in $n"; return 1; }
		grep -qF -- '"Arcade": { "$path"' "$ZN_ROOT/$n/default.project.json" || { echo "no library mapping in $n"; return 1; }
		[[ -f $ZN_ROOT/$n/tests/lib/place.luau && -f $ZN_ROOT/$n/tests/place/library.spec.luau ]] || { echo "no place tier in $n"; return 1; }
		[[ $n == pickman ]] && continue
		bash "$ZN_ROOT/$n/check.sh" --full || { echo "the gate of $n failed"; return 1; }
	done
	grep -qF -- "\"Arcade\": { \"\$path\": \"$lib/shared\" }" "$ZN_ROOT/pickman/default.project.json" &&
		grep -qF -- "\"Arcade\": { \"\$path\": \"$lib/server\" }" "$ZN_ROOT/pickman/default.project.json" &&
		bash "$ZN_ROOT/pickman/check.sh" --affected --base HEAD
}
check "AC4: all six homes have the arcade alias, map the library in their default place and have the place tier, the rule holds them to it, and the five new gates and pickman's static stages pass" ac4

ac5() {
	[[ -f $ZN_ROOT/z-nile/tests/lib/place.luau ]] || { echo "no shared place harness"; return 1; }
	grep -qF -- 'return require("../../../z-nile/tests/lib/place")' "$ZN_ROOT/pickman/tests/lib/place.luau" || { echo "pickman's place.luau is not the re-export"; return 1; }
	! grep -q 'SCRIPT_ROOTS' "$ZN_ROOT/z-nile/tests/lib/place.luau" || { echo "the script roots are still a list"; return 1; }
	lune run tests/run -- "$A/place.spec.luau" || return 1
	# pickman's place tier and the acceptance specs that load or select by its place, run from its home (named by variables:
	# they are paths of another project's home)
	local d t=tests specs=()
	for d in place acceptance/c0002 acceptance/c0041 acceptance/f0061 acceptance/f0013; do specs+=("$ZN_ROOT/pickman/$t/$d"/*.spec.luau); done
	( cd "$ZN_ROOT/pickman" && lune run tests/run -- "${specs[@]#"$ZN_ROOT/pickman/"}" )
}
check "AC5: the place harness is the shared one, reads its script roots from the project file, and pickman's place specs pass unchanged" ac5

# AC6: pickman's architecture spec, copied into a fixture home and run there: it fails a Logic require that resolves outside
# the home, a spec that requires the shared place harness itself and a client require of ServerStorage, and passes the clean home.
# The fixture is one folder under this home's .cache, made by mktemp and removed at the end. The function is here, not in a
# file beside this one: experiments/ is not sequestered, and mutants.py extracts this function from here.
ac6_fixture() {
	local top home Q="req""uire" rc=0 cache=.cache out s=src # (home-relative names are built from $s: check-paths reads a literal one as a path)
	top=$(mktemp -d "$PWD/$cache/c0185-cross.XXXXXX") || return 1
	home=$top/home
	mkdir -p "$home/$s/shared/Logic/Feature" "$home/$s/server" "$home/$s/client" "$home/tests/lib" "$home/tests/meta" \
		"$home/tests/unit/Feature" "$top/other/server" "$top/z-nile/tests/lib"
	printf '%s\n' '{ "languageMode": "strict", "aliases": { "tests": "./tests", "znile": "../../.." } }' >"$home/.luaurc"
	cat >"$home/default.project.json" <<EOT
{ "name": "home", "tree": { "\$className": "DataModel",
  "ReplicatedStorage": { "Shared": { "\$path": "$s/shared" } },
  "ServerStorage": { "Arcade": { "\$path": "../other/server" } },
  "ServerScriptService": { "Server": { "\$path": "$s/server" } },
  "StarterPlayer": { "StarterPlayerScripts": { "Client": { "\$path": "$s/client" } } } } }
EOT
	# a second place (the lobby's kind) with a server root of its own
	cat >"$home/lobby.project.json" <<EOT
{ "name": "lobby", "tree": { "\$className": "DataModel",
  "ServerScriptService": { "Lobby": { "\$path": "$s/lobby" } } } }
EOT
	printf '%s\n' '--!strict' "return $Q(\"@znile/tests/lib/t\")" >"$home/tests/lib/t.luau"
	printf '%s\n' '--!strict' 'return {}' >"$top/z-nile/tests/lib/place.luau" # the shared place harness, as the home sees it
	printf '%s\n' '--!strict' 'return { name = "receipts" }' >"$top/other/server/Receipts.luau"
	printf '%s\n' '--!strict' 'return { name = "thing" }' >"$top/other/Thing.luau"
	printf '%s\n' '--!strict' 'return { name = "feature" }' >"$home/$s/shared/Logic/Feature/init.luau"
	printf '%s\n' '--!strict' "local F = $Q(\"@game/ServerStorage/Arcade/Receipts\")" >"$home/$s/server/Main.server.luau"
	printf '%s\n' '--!strict' 'print("client")' >"$home/$s/client/Main.client.luau"
	mkdir -p "$home/$s/lobby"
	printf '%s\n' '--!strict' "local F = $Q(\"@game/ServerStorage/Arcade/Receipts\")" >"$home/$s/lobby/Boards.luau" # a server file of the second place alone
	printf '%s\n' '--!strict' "local F = $Q(\"@logic/Feature\")" >"$home/tests/unit/Feature/feature.spec.luau"
	cp "$ZN_ROOT/pickman/tests/meta/architecture.spec.luau" "$home/tests/meta/architecture.spec.luau"
	cp "$ZN_ROOT/pickman/tests/meta/tiers.luau" "$home/tests/meta/tiers.luau" # the spec requires it (R0065); user-approved edit during R0076
	cat >"$home/run.luau" <<EOT
--!strict
-- runs three cases of the copied architecture spec in this folder and prints PASS or FAIL for each
local spec = $Q("./tests/meta/architecture.spec")
for _, prefix in { "src requires:", "Logic requires resolve inside the home", "specs reach the shared place harness" } do
	for _, case in spec.cases do
		if string.sub(case.name, 1, #prefix) == prefix then
			print((if pcall(case.fn) then "PASS " else "FAIL ") .. prefix)
		end
	end
end
EOT
	out=$(cd "$home" && lune run run) || rc=1
	[[ $rc == 0 && $(grep -c '^PASS ' <<<"$out") == 3 ]] || { echo "the clean home: $out"; rc=1; }
	# a Logic require that resolves outside the home, by a relative path (the graph follows it on disk)
	printf '%s\n' '--!strict' "local T = $Q(\"../../../../../other/Thing\")" 'return T' >"$home/$s/shared/Logic/Feature/Impl.luau"
	out=$(cd "$home" && lune run run) || rc=1
	{ grep -qx 'FAIL Logic requires resolve inside the home' <<<"$out" && [[ $(grep -c '^PASS ' <<<"$out") == 2 ]]; } || { echo "an outside Logic require: $out"; rc=1; }
	rm -f "$home/$s/shared/Logic/Feature/Impl.luau"
	# a spec that requires the shared place harness itself, not the home's re-export
	printf '%s\n' '--!strict' "local P = $Q(\"../../../../z-nile/tests/lib/place\")" >"$home/tests/unit/Feature/skip.spec.luau"
	out=$(cd "$home" && lune run run) || rc=1
	{ grep -qx 'FAIL specs reach the shared place harness' <<<"$out" && [[ $(grep -c '^PASS ' <<<"$out") == 2 ]]; } || { echo "a place bypass: $out"; rc=1; }
	rm -f "$home/tests/unit/Feature/skip.spec.luau"
	# a client file requiring ServerStorage (a server file may; the clean home has one)
	printf '%s\n' '--!strict' "local F = $Q(\"@game/ServerStorage/Arcade/Receipts\")" >"$home/$s/client/Main.client.luau"
	out=$(cd "$home" && lune run run) || rc=1
	{ grep -qx 'FAIL src requires:' <<<"$out" && [[ $(grep -c '^PASS ' <<<"$out") == 2 ]]; } || { echo "a client ServerStorage require: $out"; rc=1; }
	# the same folder replicated by a third place: a ServerStorage require fails there, so it is no server file
	cat >"$home/third.project.json" <<EOT
{ "name": "third", "tree": { "ReplicatedStorage": { "Lobby": { "\$path": "$s/lobby" } } } }
EOT
	printf '%s\n' '--!strict' 'print("client")' >"$home/$s/client/Main.client.luau"
	out=$(cd "$home" && lune run run) || rc=1
	{ grep -qx 'FAIL src requires:' <<<"$out" && [[ $(grep -c '^PASS ' <<<"$out") == 2 ]]; } || { echo "a folder two places map differently: $out"; rc=1; }
	# a project file that is not a project: the server roots can't be told, so the case errors and fails (it never passes)
	rm -f "$home/third.project.json"
	printf '%s\n' '{ not json' >"$home/broken.project.json"
	out=$(cd "$home" && lune run run) || rc=1
	{ grep -qx 'FAIL src requires:' <<<"$out" && [[ $(grep -c '^PASS ' <<<"$out") == 2 ]]; } || { echo "a broken project file: $out"; rc=1; }
	case $top in "$PWD/$cache"/c0185-cross.*) rm -rf -- "$top" ;; esac
	return $rc
}
ac6() { lune run tests/run -- "$A/crosshome.spec.luau" "$A/place.spec.luau" && ac6_fixture; }
check "AC6: a Logic require that resolves outside its home, a spec that skips the home's place re-export and a client require of ServerStorage each fail pickman's structural spec, run from a fixture home" ac6

# The text of the skills is today's claim, so it is here and not in a promoted spec (docs.spec pins z-nile's own documents).
ac7() {
	lune run tests/run -- "$A/docs.spec.luau" || return 1
	local n src=src
	grep -qF -- "\`@arcade\` is the library's \`$src/shared\` (\`../arcade/$src/shared\`)" "$ZN_ROOT/pickman/skills/pickman-arch/SKILL.md" &&
		grep -qF -- 'also into `ServerStorage` (`@game/ServerStorage/Arcade/...`, c0185)' "$ZN_ROOT/pickman/skills/pickman-arch/SKILL.md" &&
		grep -qF -- 'from a server file (one that every place of the home that maps it, each `*.project.json`, puts under a' "$ZN_ROOT/pickman/skills/pickman-arch/SKILL.md" &&
		grep -qF -- 'and `tests/meta` fails any Logic require that resolves outside the home (c0185)' "$ZN_ROOT/pickman/skills/pickman-arch/SKILL.md" &&
		grep -qF -- 'reads its script roots from the project file, and the selector (`graph.placeInputs`) from every `$path`' "$ZN_ROOT/pickman/skills/pickman-arch/SKILL.md" &&
		grep -qF -- 'and so is `place` (the Rojo-built place, `z-nile/tests/lib/place.luau`, c0185)' "$ZN_ROOT/pickman/skills/pickman-test/SKILL.md" &&
		grep -qF -- 'every change to what the place is built from' "$ZN_ROOT/pickman/skills/pickman-test/SKILL.md" || { echo "pickman's skills"; return 1; }
	for n in arcade portal snake invaders asteroids; do
		grep -qF -- 'as c0185 did for `place`' "$ZN_ROOT/$n/skills/$n-test/SKILL.md" &&
			grep -qF -- "and \`@arcade\` at the library's \`$src/shared\`" "$ZN_ROOT/$n/skills/$n-test/SKILL.md" || { echo "the test skill of $n"; return 1; }
		[[ $n == arcade ]] && continue
		grep -qF -- 'The gate holds it (c0185)' "$ZN_ROOT/$n/skills/$n-arch/SKILL.md" &&
			! grep -qF -- 'Until the cross-home gate exists' "$ZN_ROOT/$n/skills/$n-arch/SKILL.md" || { echo "the arch skill of $n"; return 1; }
	done
	! grep -qF -- "how a game maps it in is c0185's" "$ZN_ROOT/arcade/skills/arcade-arch/SKILL.md"
}
check "AC7: z-nile's README and zz-test, pickman's two skills and the five homes' skills carry the restated rules" ac7

# Overrides: none. The promoted specs the change can reach, by the override-check searches, pass; and none is edited (the
# merge base is the reference: an addition is the new c0185 specs' own promotion, a modification or a deletion is an override).
ac8() {
	local base
	base=$(git -C "$ZN_ROOT" merge-base HEAD origin/main) || return 1
	[[ -z $(git -C "$ZN_ROOT" diff --name-only --diff-filter=MDR "$base" | grep -E '^(z-nile|pickman)/tests/(acceptance|tooling)/') ]] ||
		{ echo "a promoted spec is edited"; return 1; }
	local a4=tests/acceptance c4 # c0184's specs exist once it is done
	c4=$a4/c0184
	lune run tests/run -- "$c4/homes.spec.luau" "$c4/docs.spec.luau" "$c4/generic.spec.luau" \
		tests/acceptance/c0120/layout.spec.luau tests/acceptance/c0120/graph-homes.spec.luau tests/acceptance/c0120/docs.spec.luau \
		tests/acceptance/c0120/gate-homes.spec.luau tests/acceptance/c0115/layout.spec.luau tests/acceptance/c0115/docs.spec.luau \
		tests/acceptance/c0115/readme.spec.luau tests/acceptance/c0114/docs.spec.luau tests/acceptance/c0114/gate-cover.spec.luau \
		tests/acceptance/c0172/narrowed.spec.luau tests/acceptance/c0183/designs.spec.luau tests/tooling/affected.spec.luau \
		tests/tooling/game-roots.spec.luau tests/tooling/repo-fence.spec.luau tests/meta/architecture.spec.luau || return 1
	local d t=tests specs=()
	for d in meta/*.spec.luau acceptance/c0064/*.spec.luau acceptance/c0015/*.spec.luau acceptance/f0026/adapters.spec.luau acceptance/f0146/place.spec.luau; do
		specs+=("$ZN_ROOT/pickman/$t"/$d)
	done
	( cd "$ZN_ROOT/pickman" && lune run tests/run -- "${specs[@]#"$ZN_ROOT/pickman/"}" )
}
check "AC8: no promoted spec is edited, and the specs the change can reach pass" ac8

finish

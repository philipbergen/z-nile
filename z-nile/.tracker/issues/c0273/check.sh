#!/usr/bin/env bash
# Acceptance checks for c0273. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0273 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0273"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the home rule lists every *.project.jsonc of a home (and no other name), reads it as a *.project.json, reports a commented one as mapping no \$path and as not JSON to Lune's decoder while still judging what Rojo reads of it, and does not take a default.project.jsonc for the default place" \
	lune run tests/run -- "$A/jsonc.spec.luau"
check "AC2: the home rule reports <name>.project.json beside <name>.project.jsonc once per place" \
	lune run tests/run -- "$A/jsonc.spec.luau"
check "AC3: graph names a project file by both suffixes, its one lister (the server-file rule and graph.placeInputs) reads every *.project.jsonc, and a commented one stops both with an error naming the file and saying why" \
	lune run tests/run -- "$A/jsonc.spec.luau"
check "AC4: a change to a home's top-level *.project.jsonc forces that project's static run, as a *.project.json does" \
	lune run tests/run -- "$A/jsonc.spec.luau"
check "AC5: the gate plans a home's *.project.jsonc after its *.project.json files and builds it into .cache/check-<name>.rbxl" \
	lune run tests/run -- "$A/gate.spec.luau"
check "AC6: the README, zz-test, pickman-arch and arcade's architecture name *.project.jsonc wherever they say which files are a home's project files" \
	lune run tests/run -- "$A/docs.spec.luau"
check "AC7: the specs this chore touches still pass: the home rule, graph and its homes, the library wiring, c0246's net, the gate's homes, the selector, the README and skill pins, and z-nile's architecture spec" \
	lune run tests/run -- tests/acceptance/c0184/homes.spec.luau tests/acceptance/c0185/graph.spec.luau \
	tests/acceptance/c0185/library.spec.luau tests/acceptance/c0185/docs.spec.luau tests/acceptance/c0246/paths.spec.luau \
	tests/tooling/home-rojo-failclosed.spec.luau tests/acceptance/c0120/graph-homes.spec.luau \
	tests/acceptance/c0120/gate-homes.spec.luau tests/tooling/select-scope.spec.luau tests/tooling/affected.spec.luau \
	tests/acceptance/c0184/docs.spec.luau tests/meta/architecture.spec.luau
check "AC8: pickman's lobby-tooling spec (it pins the gate's *.project.json loop line), home spec and architecture spec still pass" \
	bash -c 'cd ../pickman && lune run tests/run -- tests/acceptance/f0061/lobby-tooling.spec.luau tests/meta/home.spec.luau tests/meta/architecture.spec.luau'

finish

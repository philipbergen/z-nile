#!/usr/bin/env bash
# Acceptance checks for c0246. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0246 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0246"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: graph.unreadable names every node whose \$path is neither a string nor an optional string, sorted by instance" \
	lune run tests/run -- "$A/paths.spec.luau"
check "AC2: graph.mappings and graph.gameRoots still skip those paths and keep the readable ones" \
	lune run tests/run -- "$A/paths.spec.luau"
check "AC3: the home rule reports each one with its file, node and kind of value, and a file with only such paths is not also reported as mapping none" \
	lune run tests/run -- "$A/paths.spec.luau"
check "AC4: the README states the rule" \
	lune run tests/run -- "$A/paths.spec.luau"
check "AC5: the home rule reports a library file Rojo puts anywhere but at its node, a project file Rojo loads from a mapped folder (any depth, any casing, .jsonc, through links) as a nested project and a file Rojo reads from outside the home and the library's two folders once per project file; a folder with neither and a link loop are not reported" \
	lune run tests/run -- "$A/paths.spec.luau"
check "AC6: a project Rojo loads through syncRules is judged by the files it reads, a file without the rule reads nothing, a top-level project file is never a nested project, and a rojo that cannot be run is reported" \
	lune run tests/run -- "$A/paths.spec.luau"
check "AC7: the specs this chore touches still pass: the home rule, the graph reader, the library wiring and the README pins" \
	lune run tests/run -- tests/acceptance/c0184/homes.spec.luau tests/acceptance/c0185/graph.spec.luau \
	tests/acceptance/c0185/library.spec.luau tests/acceptance/c0185/docs.spec.luau tests/acceptance/c0120/graph-homes.spec.luau \
	tests/acceptance/c0184/docs.spec.luau tests/meta/architecture.spec.luau

finish

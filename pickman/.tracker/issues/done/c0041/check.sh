#!/usr/bin/env bash
# Acceptance checks for c0041. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0041 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0041"

check "AC1: graph maps @game paths through the Rojo project" lune run tests/run -- "$A/graph-game.spec.luau"
check "AC2: graph.resolve and graph.build follow @game requires" lune run tests/run -- "$A/graph-build.spec.luau"
check "AC3: place.resolveRequire resolves @game from the tree root" lune run tests/run -- "$A/place-game.spec.luau"
check "AC4: the architecture skill documents @game for cross-root requires" \
  bash -c 'f=skills/pickman-arch/SKILL.md; for s in "@game/ReplicatedStorage/Shared/Logic/" "across Rojo roots" "only into ReplicatedStorage"; do grep -qF "$s" "$f" || { echo "missing: $s"; exit 1; }; done'
check "AC5: src may require only relative paths, @self/ or @game/ReplicatedStorage/, enforced by tests/meta" \
  lune run tests/run -- "$A/src-aliases.spec.luau" tests/meta/architecture.spec.luau

finish

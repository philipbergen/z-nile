#!/usr/bin/env bash
# Acceptance checks for c0114. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
# scripts/lib/ac.sh: on main before c0114 the helpers live there; after it, that path forwards to z-nile/lib/ac.sh
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `done` (this item moves from tracker/ to z-nile/.tracker/ during execution, so the
# folder is found from this file, never by a root path), promoted to tests/acceptance/c0114 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0114"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `members` and other cheap reads; everything else goes inside `check`.
check "AC1: z-nile/projects.toml lists the projects, and its parser refuses anything out of shape" lune run tests/run -- "$A/registry.spec.luau"
check "AC2: the engine and the build live in z-nile/, ./zn is the command, and every old path forwards" lune run tests/run -- "$A/layout.spec.luau"
check "AC3: every command works across the project roots, and a z-nile raft is readied and stopped in its own root" lune run tests/run -- "$A/roots-cli.spec.luau"
check "AC4: publish writes only under origin/main's roots, moves stay in their root, paths.rewrite matches roots" lune run tests/run -- "$A/publish-roots.spec.luau"
check "AC5: capture, history, lessons and the metrics cutoff follow an item across roots" lune run tests/run -- "$A/trail-move.spec.luau"
check "AC6: compaction renumbers every root from one counter and writes the map and counter in z-nile/" lune run tests/run -- "$A/compact-roots.spec.luau"
check "AC7: every lookup of the repository guards fails closed" lune run tests/run -- "$A/guards.spec.luau"
check "AC8: the gate, the selector, the fence scan, the .cache review, the stop hook and CI cover z-nile/" lune run tests/run -- "$A/gate-cover.spec.luau"
check "AC9: the skills, AGENTS.md, SETUP.md and the templates name ./zn, the moved paths and the root rules" lune run tests/run -- "$A/docs.spec.luau"
check "AC10: every tooling item is in z-nile/.tracker/, every game item in tracker/, and live check.sh files still list" lune run tests/run -- "$A/classified.spec.luau"
check "AC11: the guard scans pass over the moved tree" lune run tests/run -- tests/tooling/repo-fence.spec.luau tests/meta/architecture.spec.luau "$PWD/tests/acceptance/c0077/cache-paths.spec.luau"
check "AC12: the real tracker audits with no errors across both roots (an unmoved counter is a warning)" ../zn audit
check "AC13: the branch never touches tracker/next; the first publish after landing moves the counter to z-nile/next with a tombstone, and only z-nile/next is written after" lune run tests/run -- "$A/window.spec.luau"
check "AC13: this branch changes neither tracker/next nor z-nile/next" git diff --quiet origin/main...HEAD -- ../tracker/next z-nile/next
check "AC14: finished items' check.sh files name the moved paths' new locations (the user's exception for finished items)" lune run tests/run -- "$A/finished.spec.luau"
check "AC14: every item's check.sh and acceptance files are their origin/main text: unchanged if unfinished, with only the listed rewrites if finished" lune run "$A/finished.luau" "$HERE"

finish

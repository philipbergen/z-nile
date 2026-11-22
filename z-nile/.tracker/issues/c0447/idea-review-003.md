# Idea review 003

## Findings

- F1: The Problem only counts specs in `z-nile/tests/tooling/`, but many specs outside it also require engine Luau directly. That covers 128 in `z-nile/tests/acceptance`, 1 in `z-nile/tests/meta`, 24 in the game projects and 189 tracker acceptance specs. In the game projects, `pickman/tests/meta/architecture.spec.luau` and `pickman/tests/place/main-walls.spec.luau` require `@znile/lib/graph`, `portal/tests/acceptance/f0205/place.spec.luau` requires `@znile/lib/select`, and `pickman/tests/acceptance/c0064/plan.spec.luau` requires `@scripts/lib/beta`. So "at least 59" and "the count of specs that still reach engine Luau" understate the work. The Solution says every spec that reaches a deleted module must be replaced first, but the non-goal says the game projects' specs are not converted. Those two contradict each other for the game specs, so that fence can't hold. The helper list has the same gap. A seventh helper, `z-nile/tests/lib/scanners.luau`, names `@znile/engine/{paths,ids,skills,raftcheck,boundcmd,trace}` and `@znile/lib/graph` as strings, and `hostile.luau` loads them at run time. A closure over static `require`s won't see these, so the reach check would let such a deletion through.

## Verdict

revise

# Review 003: R0032 (design mode)
Inputs: working tree of prep-lobby-beta-publish on 37af3ec (uncommitted prep, round 3): R0032.md, R0032/check.sh, R0032/experiments/prototype.patch, c0064.md, c0064/check.sh, c0064/acceptance/*.spec.luau, design-review-001/002.md, design-refute-001/002.md; scripts/deploy-beta.luau, scripts/runtime-test.luau, scripts/lib/opencloud.luau, .github/workflows/check.yml, SETUP.md, default.project.json, lobby.project.json, tests/acceptance/{c0015,c0003,f0061}; f0065.md and R0034.md in the prep-game-over-to-lobby worktree (read only).
Round 2 refutations accepted. Both are fixed as described:
- F1: the split plan's game target is `{ LobbyPlaceId = <start id> }` and the legacy target is `{}`, pinned in plan.spec and deploy.spec. f0065's prep reads exactly `LobbyPlaceId` on the game place's `ServerScriptService`, and its runtime check only asks for a number, so legacy mode (0) and split mode both pass it. The two rafts can land in either order.
- F2: 1.5 and -3 are now cases.

Spot checks, with the prototype applied and then reverted (tree as found, apart from this file):
- The six c0064 specs, the narrowed c0015/workflow and c0003/pipeline, c0003 scripts and runner-e2e, and f0061/lobby-place: 81 passed, 0 failed.
- Every c0015, c0003, c0051 and c0081 spec, plus f0031/adapter, c0001/ci-workflow, c0055/setup-run and c0006/clone: 186 passed, 0 failed.
- `luau-lsp analyze` (Lune platform) on the c0064 specs and the prototype scripts is clean. stylua and selene are clean.

Override grep for every Touched path and basename: only c0015/workflow and c0003/pipeline need changes, and both are named in the Overrides line.

Repository safety is unchanged from rounds 1 and 2:
- Each spec writes only under its own `.cache/c0064-*`.
- The deploy builds in `mktemp -d`.
- The fakes listen on loopback only.
- No `check.sh` command writes anything.

Outside this raft: R0034's Risks still say "it, or a follow-up chore, must set `LobbyPlaceId`". That is now stale because c0064 sets it. It belongs to R0034's prep, not to this review.

### F1 [low] plan.spec's legacy loop never runs its `nil` case
Where: tracker/issues/c0064/acceptance/plan.spec.luau, "without the game place's id: only the game, to the start place, as before, with a notice" (`for _, game in { (nil :: any) :: string?, "" } do`)
Evidence: generalized iteration skips the nil hole at index 1. A scratch script running exactly this loop under Lune printed `count 1`, with only `""` iterated. So the unset-variable path (running by hand, or a runner that leaves the variable out) is never checked for `split = false`, the exact game target or the notice. The nil path is still partly covered: `target finds a place ...` calls `plan(nil)` and checks the game's placeId and that there is no lobby. So a mutant that sends nil into the place-id check still dies there. A mutant that drops the notice or the attributes only when the variable is nil survives.
Recommendation: loop over a list that can't have holes, for example `for _, game in { "<nil>", "" } do local p = plan(if game == "<nil>" then nil else game)`, or write two explicit calls. No new rule, and nothing else changes.

Verdict: approve

# Review 001: R0141 (code mode)
Inputs: `2d7fa1dad26bb9da9f51cd992550aa1044fbca4e` (`R0141/1/f0211`), `git diff origin/main...HEAD` against `origin/main` `e3d17b162` after `./zn sync --fetch`; `f0211.md`, `f0211/check.sh`, `f0211/acceptance/*.spec.luau`, `f0211/results.txt`, `f0211/acceptance/watch.txt`, `f0211/experiments/{E1-walls,E7-respawn}.luau`; `R0141.md`, `R0141/check.sh`; `snake/.tracker/architecture.md`, `snake/.tracker/game-design.md`; `snake/src/shared/Logic/Maps/init.luau`, `snake/src/shared/Logic/World/init.luau`, `snake/tests/unit/Maps/{maps.spec.luau,maps.watch.txt}`, `snake/tests/unit/World/{world.spec.luau,world.watch.txt}`.

What I ran and checked (in `.worktree/R0141`):
- Sequestration (`git diff --find-renames=100% --name-status origin/main...HEAD -- snake/.tracker/issues/active/f0211/check.sh snake/.tracker/issues/active/f0211/acceptance` and across all `*/.tracker/**/check.sh` and `*/.tracker/**/acceptance/**`): lists only `A snake/.tracker/issues/active/f0211/acceptance/watch.txt`, which `./zn finish` generated from this layer's two source files (`snake/src/shared/Logic/Maps/init.luau`, `snake/src/shared/Logic/World/init.luau`; lesson `zz-review/finish-watch-is-generated`). No `check.sh` or acceptance `.spec.luau` changed.
- `./zn check f0211`: 6/6 criteria passed (AC1–AC6 all `PASS`).
- `./zn promote-check R0141`: `promote-check OK` (12 passed, 0 failed, 1 spec files).
- `z-nile/check.sh --affected`: `GATE PASSED (affected)` in 5.0 s (stylua, selene 0 errors / 0 warnings, Roblox & Lune `luau-lsp analyze`, `rojo` build `snake/default.project.json`, `snake`: 5 passed, 0 failed across `maps.spec.luau` (3) and `world.spec.luau` (2); other projects: no specs affected).
- `cd snake && lune run tests/run -- tests/meta/architecture.spec.luau tests/meta/home.spec.luau tests/place/library.spec.luau`: 15 passed, 0 failed, 3 spec files (`architecture` 12, `library` 2, `home` 1).
- Bounded benchmark runs (`cd snake && ../zn run --time 60 -- lune run .tracker/issues/active/f0211/experiments/{E1-walls,E7-respawn}.luau`): worst `Maps.roll` up to map 40 is 1.12 ms (1 player) / 0.29 ms (24 players); 24-player 1/30 s random play is 0.038 ms/tick; `World.safest` for 24 players on map 20 (`side = 79`) is 1.78 ms (< 5 ms budget); 25-apple start is 5.18 ms (0.207 ms/apple, < 1 ms budget).
- Architecture, correctness, repository safety, bounded commands: `Maps/init.luau` and `World/init.luau` are `--!strict` pure Logic (no engine words or `@game`, `dt` and `Draw` passed as parameters, `World -> Maps` declared in `snake/.tracker/architecture.md`), match `f0211`'s `TUNING`, types, simultaneous collision/growth/clear semantics, 1e-9 s `World.advance` tolerance with timers-before-step ordering, and O(side^2) two-BFS `World.safest`; no scripts, guards, or unbounded commands added.

### F1 [medium] Unit specs omit event coordinates, `"V"` walls, `Maps.nearMiddle`, full turn/step directions, and validation errors on 4 of 6 functions
Where: `snake/tests/unit/Maps/maps.spec.luau:7-35`, `snake/tests/unit/World/world.spec.luau:11-25` (against `f0211.md:96`, `f0211.md:128-135`, `f0211.md:243`)
Evidence:
- `f0211.md:243` specifies unit specs covering what the acceptance specs don't name directly (`Maps.turn`, `Maps.wallTiles`, `Maps.spawnTiles`, `World.goal`, `World.speed`, the events' fields), and `f0211.md:96` requires `side`, `speed`, `goal`, `wallCount`, `spawns`, and `roll` to raise an error naming the function when a count or map is not a whole number >= 1.
- `world.spec.luau:16` checks only `t.expect(events[2].kind).toBe("placed")` and never asserts `.id`, `.x`, `.y`, or `.heading` on `placed` (nor do `deaths.spec.luau:361` or `progress.spec.luau:241`, which check only `kind` and `id`). Similarly, neither `world.spec.luau` nor `food.spec.luau:89` checks `.x` and `.y` on `ate`, and `world.spec.luau` omits `go`, `died`, `over`, `cleared`, `World.advance` invalid `dt` (`0`, `-1`, `0/0`, `math.huge`), and `World.turn` invalid turn strings (`"Back"`).
- `maps.spec.luau:7-35` tests only 3 of 8 `(heading, side)` pairs in `Maps.turn` (omitting `E`, `S`, and `W`/`Right`), 2 of 4 headings in `Maps.step` (omitting `S` and `W`), only `"H"` in `Maps.wallTiles` (never `"V"`), only `"E"` indices 1/4/7 in `Maps.spawnTiles` (omitting indices 2/3/5/6 and `N`/`S`/`W`), only 2 of the 6 validated functions (`Maps.side(0)` and `Maps.goal(1.5)` — never `Maps.speed`, `Maps.wallCount`, `Maps.spawns`, or `Maps.roll`), and never calls `Maps.nearMiddle`, `Maps.wallMax`, or `Maps.wallCount`. Because `Maps/init.luau:224-238` pre-clamps map 2 candidates to `middleReach` and `acceptance/maps.spec.luau` tests `ones` only on map 8 (`:305`), no spec in the suite calls `Maps.nearMiddle` or detects an off-center wall accepted by `Maps.nearMiddle`.
Critique: Downstream issues (`f0212`, `f0213`) consume `placed` (`x, y, heading`), `ate` (`x, y`), and `Maps` helpers directly. Leaving event coordinates, `"V"` wall expansion, `"S"`/`"W"` directions, `Maps.nearMiddle`, and 4 of 6 error checks unpinned lets regressions in those public contracts pass every spec. The tempting fix is to check `placed`'s fields alone in `world.spec.luau` and leave the rest uncovered.
Consequences: Adding these cases to `snake/tests/unit/{Maps/maps,World/world}.spec.luau` touches no sequestered files and requires no design change; `maps.watch.txt` and `world.watch.txt` already watch both `Maps/init.luau` and `World/init.luau`. Re-finishing `f0211` updates `results.txt`.
Recommendation:
1. Expand `snake/tests/unit/Maps/maps.spec.luau` to cover all 4 headings in `Maps.step` and all 8 `(heading, side)` pairs in `Maps.turn`; `Maps.wallTiles` for both `"H"` and `"V"`; all 7 positions of `Maps.spawnTiles` across `"N"`, `"E"`, `"S"`, `"W"`; `Maps.wallCount`, `Maps.wallMax` (side < 12 -> 4, 20 -> 6, 79 -> 26), and `Maps.nearMiddle` (true inside `middleReach`, false outside on x and y for both `"H"` and `"V"`, odd and even `side`); and `toThrow("<fn>")` for all 6 functions (`Maps.side`, `Maps.speed`, `Maps.goal`, `Maps.wallCount`, `Maps.spawns` on both `side` and `players`, `Maps.roll` on both `map` and `players`) across `0`, `-1`, `1.5`, `0/0`, `math.huge`, and non-number.
2. Expand `snake/tests/unit/World/world.spec.luau` to assert exact fields on every `Event` variant (`map`, `placed` with `id, x, y, heading`, `go` with `id`, `ate` with `id, x, y`, `died` with `id, x, y`, `over` with `id`, `cleared` with `map, ids`), `World.advance` returning `{}` on `dt <= 0`, `0/0`, `math.huge`, and `World.turn` refusing `"Back"`.
Lesson: zz-test/seed-every-enumerated-case
Erred: zz-test
Upstream: none

### F2 [low] `f0211.md` lacks the Phase 2 Verification log entry before `./zn finish f0211`
Where: `snake/.tracker/issues/active/f0211/f0211.md:353-354`
Evidence: `## Verification log` contains only the placeholder comment `<!-- Appended at the end of execution: date, commands run, results. -->`, whereas `zz-execute` Phase 2 step 4 requires appending a Verification log entry and committing it before `./zn finish <issue>`.
Critique: Leaving the log empty omits the author's record of checks run and any deviations when finishing the layer. The tempting fix is to defer it to Phase 5 step 1, leaving no Phase 2 log on the finished layer.
Consequences: Appending the Verification log entry updates `f0211.md` on the layer and rides into the re-finished commit alongside F1's unit spec fixes.
Recommendation: Append a `## Verification log` entry in `f0211.md` with the date, commands run (`./zn check f0211`, `./zn promote-check R0141`, `z-nile/check.sh --affected`), observed pass counts, and `Deviations: none` (or any adjustments made), committed before re-finishing `f0211`.
Erred: zz-execute
Upstream: none

## Judged criteria
`f0211` has no Judged criteria ("### Judged: None."), so there is nothing to rule on.

Verdict: changes

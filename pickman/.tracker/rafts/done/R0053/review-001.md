# Review 001: R0053 (code mode)
Inputs: HEAD 59a2ae81 (branch R0053-risky-wall-picks, PR #206); `git diff origin/main...HEAD` (origin/main 9003f5fd after `git fetch`); R0053.md and its check.sh; f0126.md, its check.sh, `acceptance/` and `experiments/` (prototype.patch, mutants.py); pickman-arch, pickman-test, zz-test; `./zn lessons --skill zz-review --full`, `./zn lessons --when build --full`.

Evidence run:
- `./zn check f0126`: 12/12 criteria passed, RC 0.
- `z-nile/check.sh --project pickman --full`: 1543 passed, 0 failed, 238 spec files, `GATE PASSED (full)`.
- Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` lists nothing.
- The code is `experiments/prototype.patch` as applied: every `diff --git` path in the patch matches the src diff, and no hunk was edited by hand (verification log). So the places to check were where the patch, cut against the f0110, f0146 and f0109 prototypes, meets their landed code. Searches for readers that would miss the holes: `grep -n "s\.maze" Session/init.luau` finds only `join` (spawn, pellets, ghost set, cache seed, first marks) and the frame's `maze = s.maze.id`. `grep -rn "Maze.layout(" src/client src/shared/Logic/{Awareness,View,Hud}` finds only Main's first build (which `rewall` then replaces) and `View.frameMaze`. DangerHud takes the maze it is pushed (`View.frameMaze(frame)`), and f0109's landed `MazeView.flash`, `MazeView.edible` and `DangerHud.wallState` work with the patch's `wallColorOf(model, marked?)` and `paint`. `Pad.BUTTONS` keeps landed f0146's `ButtonA = "Jump"` (not the X the design text quotes), and Controls binds every `Pad.BUTTONS` key code (`for name in Pad.BUTTONS`), so Y reaches `action == "Pick"`.
- Probes and mutants were run in a `$TMPDIR` clone (`git clone --no-hardlinks`, deleted afterwards):
  - `playAgain` after a game over emits `Ready again` from `Game.playAgain` itself and not from a later step, so `freshMaze` runs once per new run. The marks after a game over were `3,7 8,11 19,4` and after `playAgain` `7,8 20,24 7,28`, with no second reroll.
  - `View.frameMaze` cache that never invalidates (`if lastMaze then`): killed by parts/views/adapters (38 passed, 4 failed).
  - `mazeOf` cached by list identity only (holes added later go unseen): killed by pick/ghosts (28 passed, 3 failed).
- Read against Behaviour 1–10, the reset table, the authority section and the step order of Implementation step 5. Every cell of the reset table matches `teleport`, `freshMaze`, `playAgain` and the Ready branch, and the reordered Ready (`freshMaze` before `teleport`) makes the spawn use the fresh maze. Server authority holds: `Pick` carries nothing, and only `armed` is set.

### F1 [low] The View unit case "the frame's maze is cached for the same holes, and rebuilt for others" never checks the rebuild
Where: pickman/tests/unit/View/marks.spec.luau, the 4th case
Evidence: I applied the mutant `if key == lastKey and lastMaze then` → `if lastMaze then` (a cache that never invalidates) to View in the clone and ran `lune run tests/run -- tests/unit/View/marks.spec.luau`: `5 passed, 0 failed`. The case only calls `frameMaze` twice with the same frame and compares the result with `Maze.layout("classic")`. The acceptance specs do kill this mutant (see above), so no behaviour is unguarded today, but the unit case's name says something it doesn't check.
Critique: A unit case whose title says more than its asserts gives false confidence when someone later narrows the acceptance specs (f0147 must narrow some of f0126's).
Consequences: Adding the missing step means a frame with one opened tile. That needs a real interior wall of classic, such as (14, 10) from E3, and nothing else.
Recommendation: In the same case, call `View.frameMaze` with `walls.opened = { { x = 14, y = 10 } }` and assert that `Maze.kind(result, { x = 14, y = 10 }) == "empty"` and that the result is not `m1`. Then call it again with the first frame and assert the tile is a wall again.

### F2 [low] Two other added unit cases can't fail for the reason their names give
Where: pickman/tests/unit/Touch/pick.spec.luau "…and without it the half of the screen"; pickman/tests/unit/Session/pick.spec.luau "the same seed marks the same walls"
Evidence: The Touch case's expectation is `if x < 400 then "turn" else "look"`, worked out from the same rule `Touch.zone` uses, so it pins nothing about where PICK sits. In the probe `Touch.pickRect` gives `555 276 70 70`, so it is always "look". The Session case only checks that one seed is deterministic, with no case where two seeds differ, so a session that always marked the first three candidates would pass it. The acceptance picks.spec covers "seeded and spread" (R5).
Critique: These are weak tests by zz-review code-mode item 3 (no negative case), but the sequestered specs cover the rules, so this is low.
Consequences: none.
Recommendation: Assert the literal `"look"` (PICK is on the right half on that box). Add a second seed whose marks differ, picking the seed pair by a search that errors if none differs (zz-test no-vacuous-pass).

### F3 [low] Implementation step 4's "unit cases in each feature's unit spec" was done for Movement and Hop only
Where: pickman/tests/unit/{Game,Blaster,Ghosts,Maze} (no f0126 cases); f0126.md Implementation step 4; Verification log
Evidence: `grep -rn "useMaze\|Blaster.gain\|Game.power(.*,\|Maze.open" pickman/tests/unit` finds nothing. These four additions (`Game.power`'s factor, `Blaster.gain`, `Ghosts.useMaze` and its refusal, `Maze.open`/`opened`) are covered only by the acceptance `parts.spec`, `boons.spec` and `maze.spec`, which are promoted at `done`. The Verification log lists the eight unit files and doesn't record this as a deviation.
Critique: The coverage survives promotion, so nothing is unguarded. The gap is between the plan and what was done, and the log doesn't say so.
Consequences: none.
Recommendation: Add one small case each to `tests/unit/{Game,Blaster,Ghosts,Maze}`. For `Ghosts.useMaze`, include the refusal of another id and of another size, which differ (zz-test guard-needs-its-own-case). Or record the deviation and its reason (covered by promoted acceptance) in the Verification log.

### F4 [low] Stale and misplaced comments, and a duplicated colour literal
Where: pickman/src/shared/Logic/Hud/init.luau:191; pickman/src/shared/Logic/Touch/init.luau:215; pickman/src/client/HudView.luau (`HudView.pick`, the banner's `TextColor3`)
Evidence:
- `Hud.pickBox`'s comment says "the bar a little below the middle (under the crosshair…)", while `Hud.PICK_BAR_AT = 0.4` puts it above the middle (design review 004 F2's move).
- `-- Every touch control's rectangle.` now sits above `Touch.pickRect`'s comment, no longer next to `Touch.buttons`.
- HudView declares `GOLD` and then writes the banner's colour as a second `Color3.fromRGB(255, 215, 0)`.
Critique: These mislead the next reader (d0149 will rework these exact files).
Consequences: Deriving HudView's gold from `View.WALL_MARKED_COLOR` would add a `View` require to HudView, which closed-table stub loaders could refuse (pickman-test lesson stub-loaders-fall-back). Don't do that here.
Recommendation: Fix the two comments and use `GOLD` for the banner. Leave HudView's requires alone.

### F5 [low] Main builds every wall twice on the first frame of a maze
Where: pickman/src/client/Main.client.luau (the `built ~= frame.maze` branch, then `key ~= wallsKey`)
Evidence: After `MazeView.build(m)`, `wallsKey = nil`, so the same frame then calls `MazeView.rewall`, which destroys the roughly 150 wall parts just made and builds them again.
Critique: It happens once per maze, so it costs little, but it is wasted work on the client's busiest frame.
Consequences: Setting `wallsKey` in the build branch would skip the first frame's marks, because `build` draws no marks. So the build itself would have to take the marks.
Recommendation: Leave it as it is, or let the build branch call `MazeView.build(View.frameMaze(frame))` followed only by the rewall, so the plain build doesn't happen. No spec change is needed either way: views.spec checks "once per walls key".

## Judged criteria (code mode only)
f0126 has no Judged criteria ("### Judged: None").

Verdict: approve

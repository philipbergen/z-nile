# Review 001: f0216 (design mode)
Inputs: prep worktree `prep-invaders-classic-rules` at HEAD efa0c6c6 plus its uncommitted prep files: `invaders/.tracker/issues/f0216/f0216.md`, `check.sh`, `acceptance/*.spec.luau` (7), `experiments/{prototype.patch,mutants.py,bench.luau}`, `invaders/.tracker/architecture.md`; `./zn capture f0216` (capture d7714681); `invaders/.tracker/game-design.md` (Invaders); the invaders-arch, invaders-test, z-design, zz-review skills.

Reviewer runs (all bounded, no file left in the repository):
- `./zn check f0216` on the branch: AC1 to AC7 fail on `could not resolve child component "Classic"` (good, red before the code); **AC8 passes with no feature present** (F7).
- `stylua --check invaders/.tracker` (the gate's format stage reads each `.tracker/`): **exit 1**, `Diff in invaders/.tracker/issues/f0216/experiments/bench.luau` (F5).
- `lune run z-nile/affected -- <the nine Touched paths>` prints nothing; `grep -rlF` of the four `Logic/<Feature>` paths over every home's `tests/acceptance` finds nothing. `Overrides: none` holds.
- A spot-check of **12 mutants that are not in the Rules table**: `./zn run --time 900 -- python3 -I <scratch script>`. It clones the repo into a fresh `mktemp -d`, copies the item folder in, applies `prototype.patch`, edits `Classic/init.luau` once per mutant, runs all seven acceptance specs and deletes the clone. Intended: 59 passed, 0 failed. **Every one of the 12 mutants: 59 passed, 0 failed.** The edits are quoted in F1 to F4 so they can go into `mutants.py`'s `M` list as they stand.

### F1 [high] The same-tick order rules the Design says are pinned have no failing case, and one wrong order softlocks the run
Where: f0216.md, Design › `Classic` "One tick while playing, in this order (the order is a rule; each case below pins its part)", steps 3 to 5; Edge cases, first bullet; Rules and mutants (no row).
Evidence: three mutants of the prototype pass all 59 cases:
- **CW**: the clear is decided after the alien shots. Swap the `if cleared then … end` block with the `if moveBombs(g, events) then … end` block. Suppose the cannon's shot kills the last alien in the same tick a bomb reaches the cannon. Then `CannonHit` runs and returns, the `waveclear` branch never runs, and the field is left with `formation.live == 0`. After the dying pause, `moveShot` can never return "cleared" again (there is nothing to kill). `Formation.tick` returns nil, `fireBomb` returns early, and the ship needs 8 aliens. The run sits forever with no aliens: **a softlock that check.sh passes**.
- **HT**: a cannon hit does not end the tick. Delete the `return events` after the `dying`/`endGame` branch. On the hit tick the formation still marches (it can invade, so a run lost on its last life gets a second `GameOver` and `reason` turns into `"invasion"`, the wrong reason on f0219's boards), and `fireBomb` can put a new bomb on the field after "removes every shot".
- **FB**: the formation ticks before the alien shots. Swap the `moveBombs` block with the `Formation.tick` block. Then "a hit on the cannon ends the tick before the formation moves (no invasion that tick)" is false.
Why no case catches them: the only clear case (`waves :: clears the wave…`) puts its bomb at x = 150 with the cannon at 112, so no hit is possible. The hit case (`lives :: loses a life…`) sets `formation.elapsed = 0`, so the formation could not have moved that tick anyway, and `reloadElapsed = -100000`, so `fireBomb` cannot fire. The Edge cases bullet states all three outcomes, and none of them has a row.
Critique: the Design makes the order a rule and says the cases pin it, but they don't. The author's likely fix is to add just one "clear + hit" case. That still leaves HT and FB alive, and the case could also be built so the bomb lands one tick after the clear, which proves nothing.
Consequences: no rule changes, because the order is already stated. Each new case needs a fixture where *both* events are due on the same tick. Otherwise it is vacuous.
Recommendation: add rows and cases, and run CW, HT and FB through `mutants.py`:
1. `waves :: the clear wins over a cannon hit in the same tick`. One alien left in column c. The cannon's shot one tick short of its box (for example, place `g.shot` by hand). A bomb at `{ x = g.cannon, d = cannonDepth }`. Expect the tick's kinds to be `{ "AlienHit", "WaveClear" }`, `lives` unchanged, phase `waveclear`, and `WaveStart` 120 ticks later. Kills CW.
2. `lives :: a hit ends the tick: no march, no alien fire, no invasion`. The formation one advance above the line (`d = invasionDepth + rowStep`) with `elapsed = interval - 1`, so it is due this tick. `reloadElapsed = reloadTicks(score) - 1`. A bomb one unit above the cannon. Expect kinds `{ "CannonHit" }`, `formation.d` unchanged, `#bombs == 0` through the pause, phase `dying`. With `lives = 1`, expect `{ "CannonHit", "GameOver" }` with reason `"lives"`. Kills HT and FB.
3. Optional (reasoned, not run): two bombs reach the cannon on one tick and cost one life.
Lesson: z-design/spec-design-correspondence ("Does every outcome stated under Edge cases … have its row and case too?")

### F2 [high] AC2's "erased by marching aliens" passes when only an advance erases
Where: Design › Barriers "Aliens erase"; `Classic` step 5 ("A step or an advance erases every block a living alien's box overlaps"); AC2; row B7; `barriers :: is erased where marching aliens overlap it`.
Evidence: mutant **ES** in `Classic/init.luau`: `"\tif moved then\n\t\teraseUnder(g)\n"` → `"\tif moved then\n\t\tif moved == \"advance\" then\n\t\t\teraseUnder(g)\n\t\tend\n"`. Result: 59 passed. The only erase case breaks out of its loop on the first `Advance`, so no sideways step through a bunker is ever observed. B7's mutant (no erase at all) is the only one listed.
Critique: game-design.md's captured rule is "that aliens marching through erase". With ES, the formation advances into a bunker, erases one slice and then steps sideways for about 18 steps through blocks it never removes. Those blocks then sit inside living aliens' boxes. Because the shot checks blocks before aliens, they also shield those aliens. A real player sees this, and AC2 passes it.
Consequences: the fixture must keep running past the advance until a sideways step happens while the aliens overlap the bunker. The `eraseBox == 0` check must run after that step, not only after the advance.
Recommendation: extend the case (or add `barriers :: a sideways step through a bunker erases too`). After the first `Advance` into the bunkers, step until the next `March`. Assert that `Barriers.count` fell on that `March` tick, and that every living alien's box then overlaps no block. Add the row (B8 "a step erases too | … | only an advance erases | run") and run ES.
Lesson: z-design/spec-design-correspondence

### F3 [medium] The wave start and revive resets are unpinned, the revive's cannon assertion cannot fail, and the Design's two reset lists disagree
Where: Design › Pauses ("waveclear ends with … a new ship timer, the reload at 0 and the cannon at its start"); The revive ("… no shots, a new ship timer, the cannon at its start, playing"); `waves :: revives only at game over…` and `waves :: clears the wave…`.
Evidence: mutants on the prototype's `startWave`, which is shared by the next wave and the revive. All three give 59 passed:
- **WC**: `"\tg.reloadElapsed = 0\n\tg.cannon = c.cannonStart\n"` → `"\tg.reloadElapsed = 0\n"` (the cannon stays where it was).
- **WR**: `"\tg.bombs = {}\n\tg.reloadElapsed = 0\n\tg.cannon"` → `"\tg.bombs = {}\n\tg.cannon"` (the reload count carries over).
- **WM**: `"\tg.mystery = Mystery.new(c.mystery)\n\tg.shot = nil"` → `"\tg.shot = nil"` (a ship crossing at game over keeps crossing after the revive, and its timer runs on).

`waves.spec.luau:146` checks `g.cannon == cannonStart` after a revive. But the case never moves the cannon: `Classic.new` puts it at 112 and `invade` gives no input. So the check is true for any implementation. The clear case likewise sets `g.cannon = 112` before the clear. Also, the revive's list omits "the reload at 0" while the wave start's list has it, and neither list says whether the alien slot turn (`nextSlot`) or the ship's side resets.
Critique: "restarts that wave from its starting depth" is a captured outcome (AC6). A revive that leaves the cannon where it died, a ship mid-crossing, or a half-run reload passes check.sh. The tempting fix is to add an assertion for each field, but leaving the fixture's fields at their start values keeps those assertions vacuous.
Consequences: write one "start of a wave" state that the next wave and the revive share, and list every field: formation, barriers, ship (`Mystery.new`: timer 0, first from the left, or the side carried on, but say which), shots, reload 0, `nextSlot` (reset or kept), cannon at `cannonStart`, phase, timer. Each kept or reset choice is a prep tuning, not a user decision.
Recommendation: state that one list in the Design, used by both paths. In both the clear case and the revive case, set every reset field away from its start value before the clear or the game over: cannon at 40, `reloadElapsed` mid-count, a ship crossing (`mystery.x = 100`, `elapsed = 700`), `nextSlot = 3`. Then assert each one after `WaveStart` or `revive`. Add rows for WC, WR and WM (and for `nextSlot` and the ship's side, whichever way you decide) and run them.
Lesson: zz-test/set-read-fields-apart; zz-test/per-member-copy-pinned-at-every-reader (each reset pinned, "does every cell of the reset table … name the mutant that was run for it")

### F4 [medium] Five more rules the Design states have no case that fails without them
Where: Design › `Classic` steps 2, 4, 5 and 6; Score and the extra life; Rules rows S1, S11, S15, L7 and L8.
Evidence: each mutant below gives 59 passed on the prototype:
- **QF** "(not queued)": `"\tif fire and g.shot == nil then\n\t\tg.shot = { x = g.cannon, d = c.cannonDepth - 1 }"` → `"\tif fire then\n\t\t(g :: any).queued = true\n\tend\n\tif (g :: any).queued and g.shot == nil then\n\t\t(g :: any).queued = nil\n\t\tg.shot = { x = g.cannon, d = c.cannonDepth - 1 }"`. S1 kills only "a fire replaces the shot". In every case, the fire held during a flight stops before the shot ends.
- **EL** the extra life from any points: in the ship branch, `addScore(g, points, events)` → `g.score += points`. Every extra life case reaches 1,500 through an alien. A 300-point ship is the common way across 1,500.
- **LE** the cannon's left edge: `bomb.x >= g.cannon - c.cannonHalf` → `bomb.x > …`. S15 checks only the right edge.
- **IV** `March`/`Advance` carry the new interval (the beat's interface promised to f0218): delete `interval = Formation.interval(g.formation),`. No spec reads the field.
- **TIE** "the lower column on a tie": `if dist < best` → `if dist <= best`. No acceptance case puts the cannon midway between two living columns, although an integer cannon hits a midpoint (for example x = 40 between columns 1 and 2) often in play. The test plan leaves this to the executor's unit spec, which nobody reviews against a mutant.
Critique: a design with 67 killed mutants looks complete, but these five rules are written in the Design and nothing checks them. IV is an interface that a sibling issue will design against.
Consequences: none on the design. Each case needs a fixture where the wrong rule shows (QF: hold fire for the whole flight, then release before the shot ends; EL: the score just under 1,500 with the ship's value known from `shotsFired`).
Recommendation: one case and one row each, all run:
- QF: `shots :: a fire while the shot flies is not remembered`. `fire = true` for every tick of the flight, then no input once the shot is gone: expect no `PlayerFire` and `shotsFired == 1`.
- EL: `lives :: the ship's points can win the extra life`. Score 1,450, `shotsFired = 22`, so the 23rd shot is worth 300. Expect `MysteryHit` then `ExtraLife`, lives 4.
- LE: in `shots :: costs a life…`, a bomb at `cannon - cannonHalf` hits and one at `cannon - cannonHalf - 1` misses.
- IV: in `formation`/`game`, after a kill the next `March` event's `interval` equals `Formation.interval(g.formation)` (54), and the `Advance` event carries it too.
- TIE: `shots :: aims at the lower column on a tie`. Cannon at x = 40 with columns 1 and 2 alive: slot 1 fires from column 1.
Lesson: z-design/spec-design-correspondence

### F5 [medium] The gate's format stage fails on this branch, and E1's "static green" record is stale
Where: `experiments/bench.luau` line 23; Unknowns E1 ("`z-nile/check.sh --project invaders --static` green on it (format, …)").
Evidence: `z-nile/check.sh` runs `stylua --check` over `z-nile/roots --luau-dirs`, which names `invaders/.tracker` itself. `stylua --check invaders/.tracker` exits 1 with `Diff in invaders/.tracker/issues/f0216/experiments/bench.luau` (the long `print(string.format(…))` line). The acceptance specs are clean. The prep PR's gate is red as it stands.
Critique: the recorded green no longer matches the files, so a reader can't trust the record either.
Consequences: none beyond re-running the record.
Recommendation: run `stylua invaders/.tracker/issues/f0216` (the whole item folder, not only `acceptance/`), then `stylua --check invaders/.tracker`. Re-run `z-nile/check.sh --project invaders --static` with the prototype applied and record the date and result in E1.
Lesson: zz-test/format-tracker-specs-by-path

### F6 [low] E2's recorded method is an unbounded probe
Where: Unknowns E2 ("Method: `python3 -I experiments/mutants.py [ids]`").
Evidence: the method is a bare long-running script (73 spec runs). E3 is recorded through `./zn run --time 120`, but E2 is not, and the record doesn't say how it was run. Each subprocess has `timeout=600`, but nothing bounds the whole run.
Recommendation: record and run it as `./zn run --time 900 -- python3 -I invaders/.tracker/issues/f0216/experiments/mutants.py [ids]`. Re-run it that way after F1 to F4's new mutants are added, and record the new totals.

### F7 [low] Labels say more or other than their checks
Where: `acceptance/game.spec.luau` line 2 ("f0216 AC8: the game as a whole"; it is AC7); `acceptance/waves.spec.luau` line 2 ("AC6 and AC7"; it is AC6 only); check.sh AC8.
Evidence: `./zn check f0216` on the branch: `PASS AC8: the four features are engine-free Logic with declared dependencies and unit specs`, with no feature in `src/`. The meta spec checks every feature that exists. It cannot fail for a missing one, so AC8 alone does not verify "the four features".
Recommendation: correct the two header comments. Either make AC8's label say what the meta spec verifies ("every Logic feature is engine-free, requires only declared edges and has unit specs"), or add a sentence to the Design: AC1 to AC7's `@logic/<Feature>` requires are what prove the four exist.
Lesson: z-design/spec-design-correspondence ("does every check's label say exactly what its command verifies?"); zz-test/no-vacuous-pass

### F8 [low] The Maintainability claim about f0217 isn't backed for the second group's heading
Where: Design › Maintainability ("f0217 builds the two-player rules on the three leaves (their configs take a different field depth, bunker layout and formation shape) without changing the solo tables"); E2's CV2.
Evidence: `Formation` hard-codes the advance toward d = 0: `tick` does `d -= rowStep`, `front` is the lowest row, `extent`'s near edge is row 1's, and invasion is "at or below `invasionDepth`". Player 2's group advances toward the north end, and no config field reverses that. CV2 only adds an unused `toward` field, so it proves nothing about a heading.
Recommendation: don't add a heading now. Say how f0217 is expected to reuse the leaf: each group in its own mirrored frame (d' = fieldDepth − d, the erosion `travel` flipped), or a heading added later as a correct variant this issue's promoted specs must accept. Then the claim is accurate.

### F9 [low] The reading "one row" = 8 units is not in the prep choices
Where: Product decisions ("advances one row toward you", "one row closer"); The field (`rowSpacing 16`, `rowStep 8`); the prep-choices paragraph.
Evidence: both uses of "one row" are implemented as `rowStep` = 8, half the 16-unit alien row pitch (the arcade's 8-pixel drop). The prep-choices list names the 2-unit step but not this. A reader of game-design.md could fairly expect a full 16-unit row.
Recommendation: add to the prep choices: "'one row' (the advance and each wave's start) read as the arcade's drop of 8 units, half the alien row pitch".

### F10 [low] The event catalogue is spread across the steps and leaves gaps for f0218
Where: Design › `Classic` steps 3 to 7, Pauses, Maintainability ("The events are the one channel f0218 renders and sounds from").
Evidence: step 4 names no event when an alien's shot erodes a block. The prototype emits `BarrierHit` for both shots, so an executor working from the Design alone could emit it only for the cannon's. No place lists each kind's fields (`Respawn` carries `lives` in the prototype but not in the Design; `BarrierHit` carries no position or shot).
Recommendation: add one table with each of the 15 kinds, when it fires and its fields. Say whether `BarrierHit` is emitted for both shots and which shot it was (for example a `slot` field: nil for the cannon's, 1 to 3 for a bomb).

Lesson candidates (for the lead): none new. F1 to F4 repeat z-design/spec-design-correspondence and zz-test/set-read-fields-apart, F5 repeats zz-test/format-tracker-specs-by-path, and those lessons already ask the right questions.

Verdict: changes

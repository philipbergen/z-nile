# Review 002: f0126 (design mode)
Inputs: prep worktree at 9cbf93c4 plus its uncommitted prep (f0126.md, check.sh, acceptance/*.spec.luau ×9, experiments/prototype.patch and mutants.py, harvest.md, design-refute-001.md, game-design.md, architecture.md, the four lessons); `./zn capture f0126`; c0150.md, f0147.md; f0110's prep (`.worktree/prep-touch-fire-and-hop`, its acceptance specs) and prototype (`.worktree/proto-f0110` at dc6c8bf1). The prototype worktree's specs and src equal the prep's spec files and `prototype.patch` (`diff -r`, and its `git diff d66229c4` matches the patch). Every spec file in the prototype (`tests/acceptance`, `unit`, `meta`, `place`, `scenario`, `contract`, `integration` and the 9 sequestered files): 1500 passed, 3 failed (c0150's two pins, as E5 says). I re-ran `mutants.py F1 F2 F3 F4 F5 F6` (round 1's rows): all 19 killed. My own mutants ran in a `$TMPDIR` clone at d66229c4 plus the patch, against all 9 sequestered files each (runner: one-line edits to `src/shared/Logic/Session/init.luau`; the clone was deleted after).
Dropped from design-review-001: F1, F2, F3, F4, F5, F6, F7, F8, F9, F10 (all fixed; rulings at the end).

### F1 [high] f0126's new `Picks` require in Controls turns five cases of f0110's sequestered adapters spec red, and "whichever lands second merges by hand" cannot fix a sequestered or promoted spec
Where: Regression guard, "Work in flight on the same files" (R0051/f0110); Touched `src/client/Controls.luau`; f0110 `acceptance/adapters.spec.luau:141-158` (its Controls loader)
Evidence: f0110's spec loads Controls with a closed module table, `require = function(spec) return assert(modules[spec], spec) end`, listing Blaster, Hop, Maze, Movement, Touch and View only. I cloned `proto-f0110` (dc6c8bf1) into `$TMPDIR`, copied f0110's acceptance specs in, applied only f0126's Controls hunk from `prototype.patch` (it applies cleanly) and ran `lune run tests/run -- .tracker/issues/f0110/acceptance/adapters.spec.luau`: `5 passed, 5 failed`. Each failure is `adapters.spec:158: @game/ReplicatedStorage/Shared/Logic/Picks`. The failing cases are "a tap on the fire button sends the aimed shot…", "a fire tap sends nothing with no aim yet…", "a tap on the hop button sends Hop.INTENT…", "a finger held on a button and dragged away…", "the rectangles come from the called hook on each touch…". Without the hunk (with only f0126's HudView hunk merged), the same file and `hunt.spec` pass: `12 passed, 0 failed`.
Critique: the Design names R0051 and says "whichever lands second merges by hand". Neither raft can: if R0051 lands first, its spec is promoted to `tests/acceptance/f0110/` and f0126 (a feature) may not edit it, and its Overrides line doesn't name it. If f0126 lands first, R0051's executor can't edit its own sequestered spec. Either way the second raft stops. The tempting fix is to name the spec on `Overrides:` and leave it for later, but no chore exists to narrow it, and the order isn't decided.
Consequences: any fix changes one of two sequestered designs or adds a chore and a `depends_on`. Taking the wire string from a module Controls already requires adds a deps edge and changes the A1 pin. Every option has to be proven in both landing orders (z-design lesson run-the-other-rafts-specs).
Recommendation: choose one and record it in the Regression guard.
(a) f0110 is still preparing: ask its prep to make the stub loader fall back to the real Logic module for an unlisted `Shared/Logic/<Name>`, so a later require doesn't break it. f0126 then needs nothing.
(b) Controls takes the pick's wire string through View, which it already requires (for example `View.ACTIONS`/`View.intentOf("Pick")` returning `Picks.INTENT`). That adds the edge `View -> Picks` to architecture.md (acyclic: Picks needs only Maze and Movement) and moves A1's pin to View.
(c) Sequence f0126 after R0051 and add a chore, as c0150 does, that narrows `tests/acceptance/f0110/adapters.spec.luau`'s module table, with the chore in `depends_on` and the spec on the Overrides line.
Then, as E-rows, run f0110's four sequestered files on a merge of both prototypes in both orders, and run f0126's AC6 on the same merges.
Lesson: z-design/run-the-other-rafts-specs

### F2 [high] A fresh maze never has to point the ghosts back at the plain maze: on level 2 and in a new run the ghosts can still walk through the closed holes, and all 98 cases pass (the mechanism round 1 F3 found holes in)
Where: Behaviour 8 ("'Fresh' also points the member's ghosts back at the session's maze", a sentence under the table, not a column of it); Rules S13, F3 to F3e; prototype `freshMaze`
Evidence: mutant X6 deletes `if member.ghosts then Ghosts.useMaze(member.ghosts, s.maze) end` from `freshMaze`, and all 9 files still pass: `98 passed, 0 failed`. With X6, the player on level 2 (or in a new run) sees closed walls, and a ghost walks into one of last level's hole tiles: inside a wall, and visible. The only check on which maze the ghosts walk is ghosts.spec's "the ghosts walk into the holes", which looks before any fresh maze, and the source pin on `finishPick`. Every fresh-maze case is in CORRIDOR (no ghosts) or reads only `frame.walls`. This is the defect the author's new lesson zz-test/per-member-copy-pinned-at-every-reader describes, at the place a copy is reset rather than read.
Critique: round 1 F3 found the reset pinned on one path per item. The fix pinned four items × three triggers, but the reset owns at least six things: the holes for the player, the ghosts' maze, the marks (F3 below), the long hops, the fast picks and the boon. The matrix lists only the ones the author had in mind. The tempting fix is one more CORRIDOR case, which can't show ghosts, or a pin on `freshMaze`'s source.
Consequences: a ghost case after a fresh maze needs classic, a hole opened in the first run, and a new run. `playAgain` after three kills is cheap with `PLAY`-style rules plus `ghosts = true`, while clearing classic's 244 pellets is not. A negative case ("no ghost in a closed hole") is vacuous unless a ghost would have gone there.
Recommendation: question the mechanism, not just this hole. (1) Make the reset's columns the member's per-member state: player maze, ghosts' maze, marks, long hops, fast picks, boon. Give every cell a case or a reasoned "kept/fresh" with its proof. (2) Add an invariant to ghosts.spec's `drive`: in every step, no ghost and no player occupies a tile that is a wall in `View.frameMaze(after)`. It costs nothing per step and catches X6 (and X13) wherever a fresh maze happens. (3) Extend one ghosts.spec search across a new run: find a seed where a ghost stood in a hole H in run 1, then `playAgain`, play on, and require a ghost to reach the tile in front of H (so the case isn't vacuous) while the invariant holds. Add a row for X6.
Lesson: zz-test/per-member-copy-pinned-at-every-reader

### F3 [medium] "A new level or a new run … rolls new marks" is unpinned: keeping the old marks, or rolling the new ones on the old holed maze, passes
Where: Behaviour 8 ("fresh (no holes, new marks)"), game-design (prep) "closes the holes and rolls new marks"; pick.spec "a new level starts from a fresh maze: no holes and new marks" and "a new run starts from a fresh maze"
Evidence: two mutants, each `98 passed, 0 failed`:
- X1: `freshMaze` calls `Picks.mark` (a top-up) instead of `Picks.reset`, so the old marks stay.
- X16: `freshMaze` rolls the marks on `member.maze` before resetting it to `s.maze`.

Both fresh-maze cases assert only `#marked == 3` and that each mark is a pickable wall of CORRIDOR. Kept marks are that too. In CORRIDOR no wall sits behind a hole (rows 0 and 4 are the edge), so X16 can't show there. In classic, a wall marked behind a hole has, once the hole closes, no walkable neighbour: an unreachable gold wall that never unmarks for the whole level.
Critique: the edge case "a hole beside a hole: the next marks may sit deeper" is the one state X16 breaks, and no fixture has a wall deep enough to show it.
Consequences: a fixture with walls three thick (an interior row behind the pickable row) lets a mark sit behind a hole. With X16 the search must then find a seed where such a mark exists at the moment of the reset.
Recommendation: in the fresh-maze cases, assert every mark is `Picks.pickable(<the plain layout>, tile)`, and over a small seed search that the set differs from the marks before the reset in at least one seed (this kills X1). Add a thick-walled corridor case: pick the wall beside the corridor, then pick the wall behind it once it is marked (search seeds), then start a new run while a deeper wall is marked. After the run starts, every mark is pickable in the plain layout. Add rows for X1 and X16.
Lesson: zz-test/seed-every-enumerated-case

### F4 [medium] Two stated rules have no case: "firing does not waste a pick" and "a repeat restarts" the request
Where: Behaviour 5 ("Firing does not waste a pick"), Behaviour 2 ("a repeat restarts it"); game-design (prep) "firing does not waste a pick"; Rules table (no row for either)
Evidence: two mutants, each `98 passed, 0 failed`:
- X2: `stopPick(member, id, "moved", out)` right after `shoot(...)`, so any shot wastes the pick.
- X20: `if member.pick == nil and member.armed == 0 then member.armed = …`, so a repeat doesn't restart a pending request.

`grep -n 'Fire\|fire' acceptance/*.spec.luau` finds no session case that fires during a pick. picks.spec:44 lists `"Fire"` as a non-pick intent, and parts.spec:179 checks the E key.
Critique: "any key wastes it" is the natural implementation of Behaviour 5, and the (prep) rule is a fairness choice the player relies on: shooting the ghost that comes for you while you pick. X20 makes F pressed a second time only 24 − n steps long, so a player who presses again just before a mark comes in reach loses the pick.
Consequences: firing needs shots held. The `shot` boon's `withBoon("shot")` gives one, and a second pick then starts with a shot in hand. The repeat case is a boundary pair like F5b.
Recommendation: (a) a boons.spec case after `withBoon("shot")`: start the next pick, fire during it (`Blaster.intent(<a heading>)`), and expect a `Shot` event, no `PickStopped`, and `WallPicked` at `started + ticks`. (b) A pick.spec pair: Pick at k, Pick again at k + 20, and a mark first in reach at the second request's 24th step is picked (with X20 it is not). Add rows for X2 and X20.
Lesson: z-design/spec-design-correspondence

### F5 [medium] adapters.spec pins private names the Design never gives (`member.maze`, `local function finishPick`, MazeView's `local function walls`), so a correct implementation that names them differently fails a sequestered check
Where: adapters.spec "Session plays each member in its own maze…" (lines 126-132) and "the pellets survive a rebuild of the walls" (line 100); Interfaces and Implementation steps 5 and 7
Evidence: `grep -nE 'local function [a-zA-Z]+%\(|member%\.' acceptance/*.luau` gives:
- adapters.spec.luau:100 `string.match(src, "local function walls%(.-\nend")`
- :126 `Movement%.step%(%s*member%.maze%s*,`
- :128 `Blaster%.target%(%s*member%.maze%s*,`
- :131 `local function finishPick%(.-\nend`
- :132 `Ghosts%.useMaze%(%s*member%.ghosts%s*,%s*member%.maze%s*%)` inside that body

`grep -n 'member\.maze\|finishPick' f0126.md` finds no `member.maze` at all. `finishPick` appears only in Maintainability and in two Rules rows, never as "a local function that itself calls `useMaze`". MazeView's `walls` helper isn't named anywhere. An executor who calls the field `member.world`, or puts the hole-opening in a helper called from `finishPick`, writes a correct game and fails AC6, with no way to edit the spec.
Critique: zz-review code mode calls this a weak test that asserts on internals. Here it's also an executability hole: the documents alone don't say what to name things. The tempting fix is to loosen the patterns, which removes the kill for G2.
Consequences: the move and the ghosts now have behavioural cases (pick.spec's hole case, ghosts.spec's hole search, and F2's invariant), so their pins only add brittleness. The shot (G2) has no behavioural case and needs its pin.
Recommendation: drop the pins the behavioural cases cover (`Movement.step(member.maze`, the `finishPick` body). Keep G2's `Blaster.target(<the member's maze>` and the Walls-model pin, and write every name they need into the Design: in Interfaces or step 5, the `Member` field `maze` and the local `finishPick`; in step 7, MazeView's local `walls(model, m, marked, lit)` that finds `"Walls"`. Re-run A8 and G2's mutants afterwards.
Lesson: z-design/specify-every-named-artifact

### F6 [low] Three wire details in Interfaces are never asserted: the death's `PickStopped` reason, `ShotGained` only when gained, and `frame.pick.fast`
Where: Interfaces (`PickStopped {reason: … | "pause"}`, "`ShotGained` without a ghost", `Pick = {…, fast: boolean}`), Behaviour 7 `shot` ("`ShotGained` when gained")
Evidence: each of these mutants gives `98 passed, 0 failed`:
- X3: the pause reason sent as `"moved"`.
- X4: `ShotGained` emitted even when three are held.
- X18: the frame's `pick.fast` always `false`.

pick.spec's death case checks only `find(r3, "PickStopped") ~= nil`. boons.spec's "wasted at three" case runs on `Blaster.gain` alone.
Critique: these are frame and event contracts that clients and f0147 read (f0147 plugs in at events). With X4, a HUD or sound keyed on `ShotGained` reports a shot that never came.
Consequences: none.
Recommendation: assert `reason == "pause"` in the death case. Add a session case with three shots held (three `shot` boons, or a seed with three drops) and expect no `ShotGained`. Assert `pick.fast` in the wasted-fast-pick case. Add one row each.

### F7 [low] game-design.md still credits a prep choice to the user: "a hunting ghost … on that level" (a new instance of round 1 F10's defect)
Where: game-design.md "Wall picks", **The pick:** bullet (outside the (prep) bullet); f0126 Problem, the first Scope decision line ("A pick lasts as long as a hunting ghost takes to walk 10 tiles")
Evidence: the user's words are "the time it takes for a ghost to move 10 paces". The ghost's mode (normal, not tunnel, frightened or eyes speed) and the per-level scaling (43/38/34) are this prep's readings of them. The paraphrase in the user's Scope decision line adds "hunting", and the user bullet adds "on that level".
Critique: game-design.md is binding, and f0147 (sequenced next, changing every speed) will read the scaling as the user's.
Consequences: none.
Recommendation: keep the user's words in the user bullet. Add to the (prep) bullet: "the ghost is a hunting (normal-speed) ghost of the current level, so a pick shortens as levels speed up". Leave the quoted line in the Problem as the user wrote it, without "hunting".
Lesson: z-design/restated-rules-move-together

### F8 [low] The promoted specs hard-code level-1 numbers and the pellet level clear that f0147, captured and sequenced next, changes
Where: pick.spec `PICK_TICKS = 43` and `arrival()` (a tile in 4 steps at 30 units); boons.spec `FAST_TICKS = 22`, `toBe(19)`, `clearLevel` (eat every pellet); pick.spec "a new level…" (the eat-to-clear walk)
Evidence: f0147's Problem: "Level 1 is 30% slower than today, for the player and the ghosts alike", and "Clearing every pellet no longer ends a level". Once these are `tests/acceptance/f0126/`, each literal and each pellet-clear helper is a red promoted case for f0147, which then needs an override chore across several files.
Critique: zz-test lesson promoted-specs-pin-rules-not-sets. The arithmetic belongs in AC1 (`Picks.ticks(28, false) == 43` is a rule), not in every session case.
Consequences: deriving the numbers ties the cases to `Levels` and `Picks.ticks`, which AC1 pins on its own.
Recommendation: derive `PICK_TICKS`, `FAST_TICKS` and the step-per-tile count from `Picks.ticks(Levels.ghostSpeed(Movement.DEFAULT_CONFIG.speed, 1, "normal"), …)` and `Levels.playerSpeed`. Keep the literals only in picks.spec's arithmetic case. Put each level-clear walk behind one helper per file, and say in the Regression guard that f0147 overrides exactly those cases.
Lesson: zz-test/promoted-specs-pin-rules-not-sets

### F9 [low] One case title claims a situation that can't arise, and one case can pass having checked nothing
Where: boons.spec "a hop that took off before the boon keeps its own length"; boons.spec "the pill's time is announced as a power period"; Behaviour 7 `jumps` ("A hop already in the air keeps its length")
Evidence: a hop wastes a pick (Behaviour 5) and no pick starts during a hop (Behaviour 3), so no hop is ever in the air when a pick finishes. The case plays no hop at all and checks `frame.hopTicks == Hop.TICKS` with "no hop since". Behaviour 7's sentence describes an unreachable state. In the power-period case, each boon's seed loop ends with `break` and no `error` after it, so a boon that never comes first is skipped silently.
Critique: zz-test no-vacuous-pass; z-design spec-design-correspondence (a title that says more than its fixture plays).
Consequences: none.
Recommendation: rename the case to what it checks ("the frame's hop length stays Hop.TICKS until a hop starts after the boon"), and replace the Behaviour 7 sentence with that rule. Add `error("no seed grants " .. boon)` after the power-period loop.
Lesson: zz-test/no-vacuous-pass

## Rulings on design-refute-001
- F1 fixed: ghosts.spec and eaten.spec play contacts inside a pick. F1, F1b, F1c and F1d were re-run and killed. The sharpened lesson is a fair reading of why a twin run can't hold here.
- F2 fixed for the readers it names. The move, the ghosts and the shot are each killed (re-run F2, F2b, F2c). It missed the reset (F2 above), and the source pins it chose bring F5.
- F3 fixed for the four items it lists (re-run F3 to F3e, all killed). The matrix leaves out the ghosts' maze and the marks (F2 and F3 above): the mechanism is questioned there.
- F4 fixed (F4, F4b killed).
- F5 fixed (F5, F5b, F5c killed).
- F6 fixed (F6, F6b killed).
- F7 fixed: mutants.py clones into `$TMPDIR`, refuses paths outside the clone and removes it. I ran it, and the prep worktree stayed clean.
- F8 fixed: `caught` is in the union and Behaviour 5, and ghosts.spec pins it.
- F9 fixed: recorded as (prep) in Behaviour 7 and game-design.md.
- F10 fixed for the two exclusions it named. F7 above is a further instance.
- The lessons added (per-member-copy-pinned-at-every-reader, reasoned-rows-claim-testable-reasons, confirm-landed-before-removing, and the sharpened skips-leave-the-rest-unchanged) are each a lesson another raft could fail, not a restated finding.

Verdict: changes

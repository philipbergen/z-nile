# Review 001: f0126 (design mode)
Inputs: prep worktree at 9cbf93c4 plus its uncommitted prep (f0126.md, check.sh, acceptance/*.spec.luau ×7, experiments/prototype.patch and mutants.py, harvest.md, game-design.md, architecture.md); `./zn capture f0126`; c0150.md; the prototype worktree `proto-risky-wall-picks`. I ran the prep's seven spec files against a scratch copy of the prototype ($TMPDIR clone with its own repository): 83 passed. Every promoted spec in that copy: 1266 passed, 3 failed (c0150's two pins, as E5 says). I ran 16 mutants of my own on that copy, listed in the findings. The command for each was `lune run tests/run -- .tracker/issues/f0126/acceptance/*.spec.luau` after a one-line edit to `src/shared/Logic/Session/init.luau`.

### F1 [high] No spec has a ghost catch a player who is picking, so an implementation where picking makes the player invulnerable passes every check
Where: Behaviour 5 ("a death by contact … wastes it"), AC3, pick.spec "a death during the pick wastes it…", Rules S11
Evidence: the only death in the specs is `Session.kill(s, "p")` (pick.spec, death case). The CORRIDOR fixture has no ghosts, and classic.spec never lets a ghost reach a player who is standing. I ran two mutants on the prototype. Both kept all 83 cases green:
- M1: `if member.ghosts and member.pick == nil then stepGhosts(...)`. The ghosts freeze while the player picks.
- M6: `if kill and member.pick == nil then`. Ghosts walk through a player who is picking.

The Problem's risk ("a ghost can catch them while they wait") and the captured "being caught wastes the pick" therefore hold only through the kill API.
Critique: this is the feature's whole tension. An executor who writes "standing player: skip the rest of the step" (a natural `continue`) ships picks with no risk at all. The fix the author will be tempted to make is a `Session.kill` variant, which still bypasses the contact path.
Consequences: a real contact case needs ghosts, so it needs the classic maze and a seed search, plus a way to tell that the death came from contact. It also raises a rule the Design states but nothing pins: a blue ghost meeting a picking player is eaten and the pick goes on ("never silently cancelled except by the player's own key, a hop, or leaving play").
Recommendation: add a classic.spec case. Search seeds for a pick under way when a ghost reaches the player's tile. Assert a `Died` by contact (the ghost's tile equals the player's in that step), `PickStopped`, no `WallPicked`, and that the ghosts kept moving during the stand. Add a skip-leaves-the-rest case: the same seed with and without a pending pick gives identical ghost positions every step while the player stands. Add a frightened variant: an eaten ghost does not waste the pick. Give each its own Rules and mutants row (M1, M6).
Lesson: zz-test/skips-leave-the-rest-unchanged

### F2 [high] Nothing plays in a hole: the player, the ghosts and the shot could all ignore the opened maze and every check would still pass
Where: Behaviour 6 ("The wall tile opens in the member's maze … the member's ghosts walk that maze"), AC3 and AC5, Rules G1 and G2 (`reasoned`)
Evidence: three mutants kept all 83 cases green:
- M14: `Movement.step(s.maze, member.move, queue, config)`. The player can never enter a hole.
- G1: `finishPick` without `Ghosts.useMaze`. Ghosts never enter a hole, so a player standing in a nook is safe forever.
- M15: `Blaster.target(s.maze, …)`. The shot's ray uses the plain maze.

The session specs check the hole only as data (`walls.opened`, `Maze.kind(Maze.opened(...))`). In the CORRIDOR cases the player walks on past the hole. G1's stated reason, "no public observation tells which maze the member's ghosts walk", is wrong. Ghost positions are in the frame, and a hole a ghost can't enter is a safe spot the player can see.
Critique: "A finished pick removes that wall (a hole)" is a captured outcome, and today the game would only draw it. The author may be tempted to add a unit case on `Ghosts.useMaze`, which already exists (parts.spec) and doesn't reach the call site.
Consequences: the cases need a hole on the player's way. In CORRIDOR, a Left or Right at the stop centre after the pick gives one. The ghost case needs classic and a seed search. Once the player can stand in a nook, the fail-safe for a ghost there is the existing `exitsOf` reversal, which E3 covers only at unit level.
Recommendation: add these to pick.spec or classic.spec. (a) After the pick, a turn at that centre makes the player enter the hole tile (`Entered` at the hole) and stop there. (b) In classic, a player standing in a fresh hole is reached by a ghost: the ghost's tile equals the hole on some step, or the player dies there. (c) A shot fired from inside the hole out along the corridor hits a ghost in line. Change G1 and G2 to `run` with M14, G1 and M15 as their mutants.
Lesson: zz-test/pin-call-site-arguments

### F3 [high] The fresh-maze reset is pinned on only one of its paths each: holes kept into a new run, long hops kept into a new level, and fast picks and the last boon kept into a new run all pass
Where: Behaviour 8, AC3 ("a new level starts fresh"), AC4 ("until the maze is fresh"), pick.spec "a new level and a new run start from a fresh maze" (it plays only a new level), boons.spec "longer jumps last until the maze is fresh" (it plays only a new run), Rules S13 and B3
Evidence: three mutants kept all 83 cases green:
- M2b: in `playAgain`, `freshMaze(s, member)` → `member.longHops = false`. The holes and marks carry into a new run.
- M3: `longHops` cleared only in `playAgain`, not in `freshMaze`. Long hops survive a level.
- M4: `playAgain` without `member.picks.fast = 0; member.boon = nil`.

Nothing checks that banked fast picks survive a new level and a death ("Banked picks last until a new run"). The user decided the jumps boon lasts "for the rest of the level", and M3 breaks exactly that decision.
Critique: the reset has three triggers (`Ready` of reason `level`, `Ready` of reason `again`, `playAgain`) and four things to reset (holes and marks, long hops, fast picks, the last boon). Each is checked on at most one trigger, and one case title claims a path it doesn't play. AC3's text names only a new level, so the new-run half of Behaviour 8 has no criterion.
Consequences: a matrix of triggers × items is cheap in CORRIDOR. The level path needs the level-clear walk pick.spec already has, and the run path needs the three kills boons.spec already has. Respawn is the negative column: everything is kept.
Recommendation: one case per trigger (new level, new run, respawn). Each asserts all four items: holes, marks re-rolled, `hopTicks` of the next hop, the fast pick's ticks on the next pick, and `frame.boon`. The fast pick and the last boon are kept on a level and a respawn and dropped on a new run. Extend AC3 and AC4's wording to "a new level or a new run". Add rows for M2b, M3 and M4.
Lesson: zz-test/seed-every-enumerated-case

### F4 [medium] The session uses the long hop's length in three places, and only the airborne one is pinned
Where: Behaviour 3 ("no hop under way (from its take-off step until it lands: `tick < hopped + hopTicks`)"), Behaviour 7 ("the cool-down … use the hop's own length"), game-design (prep) "the same 8-step cool-down after landing"
Evidence: two mutants kept all 83 cases green:
- M11: `Hop.canStart(member.hopped, s.tick)`. After a long hop the next one starts 1 step after landing, not 8.
- M12: `hopping` computed with `Hop.TICKS`. A pick can start on steps 12 to 18 of a long hop, while the player is still in the air.

parts.spec pins `Hop.canStart(…, LONG_TICKS)` only on the pure function.
Critique: with M12 a player picks a wall from mid-air, a visible wrong game. Each call site takes the length as an optional argument, so dropping it type-checks and silently uses the default.
Consequences: none beyond the two cases. Both reuse boons.spec's `withBoon("jumps")`.
Recommendation: two boons.spec cases after the jumps boon. (a) A Hop pressed every step after a long hop takes off again exactly at `hopped + LONG_TICKS + COOLDOWN`. (b) A Pick pressed during a long hop with a mark on the way starts no earlier than `hopped + LONG_TICKS`. Add rows for M11 and M12.
Lesson: zz-test/pin-call-site-arguments

### F5 [medium] The request's own rules are only half pinned: "no movement intent this step" has no case, and the 24-step lifetime is pinned only from below
Where: Behaviour 2 and 3, Rules S9
Evidence: two mutants kept all 83 cases green:
- M9: drop `#queue == 0` from the request test. The request then stops the player and starts a pick in a step with a turn key.
- M10b: `member.armed = 40`. The lapse case presses Back at +10 (pick starts) and at +30 (no pick), so any lifetime from about 16 to 29 passes. M10 (`12`) is killed, M10b (`40`) survives.

Behaviour 3's "no movement intent this step" has no row.
Critique: the game-design (prep) line says the request "stays pending as long as a buffered turn (24 steps)". That equality is the stated rule, and a request that lingers much longer stops players who have moved on.
Consequences: the boundary case needs the stop centre's arrival step to be exact. CORRIDOR's 4 steps per tile give that.
Recommendation: (a) Add a case where Pick and a turn arrive in the same step at a centre beside a mark: no `PickStarted` in that step, and the turn is taken. (b) Add a boundary pair: a mark first in reach on step 24 after the press starts a pick, and on step 25 it doesn't. Add rows for M9 and M10b.

### F6 [medium] The pellets-back boon is never shown to bring back a power pellet, though the user chose "Dots and power pellets"
Where: Scope decision (user, 2026-10-25) on the sixth boon, Behaviour 7 `pellets`, boons.spec "pellets back: every eaten pellet and power pellet is there again"
Evidence: boons.spec's CORRIDOR is `"#.....P.#"`, which has no `o`. The case title claims power pellets, but the fixture has none to eat or restore. A `pellets` branch that restores only the dots passes. "Pellets do not count for the ghost house" also has no row and no case.
Critique: a case title that claims more than its fixture can show. The user decided this detail explicitly.
Consequences: a fixture with an `o` on the way to a mark changes which seeds `withBoon` finds. It doesn't change the CORRIDOR cases elsewhere if the fixture is local to this case.
Recommendation: give the case its own corridor with a power pellet that is eaten before the pick. Assert `frame.pellets` equals the full encoding, and that both kinds are present. Either add a case that the house's pellet counters are unchanged by the boon (classic), or say in the Design how that rule is pinned. Add a row with a dots-only mutant.
Lesson: zz-test/seed-every-enumerated-case

### F7 [medium] `experiments/mutants.py` rewrites `src/` in whatever tree it is run from, with no guard
Where: experiments/mutants.py (driver loop: `open(f,'w').write(src.replace(old,new))`, restored in `finally`)
Evidence: the script's only safety is its header comment ("Run from pickman/ in a prototype tree"). Once f0126 lands, every anchor matches the real `src/`. Run from the main checkout, or from a raft worktree in Phase 1 or a code review, it edits tracked source in place. A kill or a timeout outside the `try` (for example Ctrl-C between the write and the `try`) leaves a mutant in the tree. It rides into `main` with the issue folder.
Critique: zz-test says commands that change anything run in a fixture under `.cache/<unique>` or a `$TMPDIR` clone, and the runner's jail does not cover a hand-run python script.
Consequences: none for the game. The script needs a copy step.
Recommendation: make the script clone the tree it is given into `$TMPDIR` (`git clone --no-hardlinks`, as zz-test's "Running specs against unguarded code" says) or into `.cache/<unique>`, and run the mutants there. It should refuse to run in a checkout whose `git rev-parse --git-common-dir` is the project's repository.

### F8 [low] The death's `PickStopped` reason differs between the Design and the prototype, and no spec pins it
Where: Interfaces (`PickStopped {reason: "moved" | "hopped" | "pause"}`), Behaviour 5 (a death wastes the pick "at the next step's start (`"pause"`)"), prototype `stepGhosts` (`stopPick(member, id, "caught", out)`)
Evidence: on ghost contact the prototype emits `reason = "caught"` in the same step, a value outside the Design's union. pick.spec's death case asserts only `find(r3, "PickStopped") ~= nil`, through `Session.kill`.
Critique: an executor copying the patch ships a reason the documented type doesn't have.
Consequences: whichever is chosen, F1's contact case should assert it.
Recommendation: choose one of these and pin the reason in the death cases. Either keep the union and remove the contact-time `stopPick`, so the next step's `"pause"` does it, or add `"caught"` to the union and to Behaviour 5.

### F9 [low] A long ghost pill shows a full power bar for its first half
Where: Behaviour 7 `longpill`; `Hud` power share (`math.clamp(play.frightened / Levels.frightenedTicks(level), 0, 1)`)
Evidence: with twice the level's time, the share is clamped to 1 for half the pill, then drains as usual.
Critique: this is the boon's only visible cue besides the banner, and the player can't tell how long it has left. The clamp prevents a broken bar.
Consequences: showing the true share needs the period's length in the frame, a new field.
Recommendation: either record in the Design that the bar stays full for the first half of a long pill (a (prep) choice the user may veto), or carry the period's length and make the share relative to it, with a Hud case.

### F10 [low] game-design.md attributes two prep choices to the user, and one sentence states the risk backwards
Where: game-design.md "Wall picks", the **Marked walls** bullet; f0126 Usability
Evidence: two choices are listed under the user's decisions, not in the **(prep)** bullet:
- "no door or house tile is among its eight neighbours"
- "the player can walk next to it"

The user said only "only interior walls". Separately, Usability says "43 steps is longer than a ghost needs to cross 10 tiles". By the design's own arithmetic, 43 steps is exactly that time, rounded up.
Critique: game-design.md is binding. Later preps will treat these choices as the user's and won't offer them for veto.
Consequences: none.
Recommendation: move the two exclusions into the (prep) bullet. Reword the Usability sentence to "a ghost 10 tiles away reaches the wall before the pick ends".

Verdict: changes

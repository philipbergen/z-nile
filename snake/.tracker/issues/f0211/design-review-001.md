# Review 001: f0211 (design mode)
Inputs: prep worktree `prep-arena-maps-growth` at 8958975b with its uncommitted draft: `snake/.tracker/issues/f0211/f0211.md`, `check.sh`, `acceptance/{maps,moves,food,deaths,progress,play}.spec.luau`, `experiments/E1-walls.luau`, `experiments/mutants.py`, and the `snake/.tracker/architecture.md` diff. Also the prototype `.worktree/proto-f0211` (8958975b plus its untracked `Logic/Maps` and `Logic/World`; its acceptance specs and check.sh are byte-identical to the prep's), `./zn capture f0211` (d7714681, no marker), `snake/.tracker/game-design.md`, and f0203's draft (`Rng.int` 1..n, `Rng.int(g, 0)` an error).
Spot checks ran on scratch copies of the prototype's two modules and the six specs, under the ignored `snake/.cache/` of this worktree (own `.luaurc`, `lune run tests/run` from `snake/`, every command through `./zn run --time`). All 71 runner mutants were re-run on the final specs: all killed (M17 by timeout), C1 to C4 green. The extra mutants and probes are named in the findings.

### F1 [high] AC2's "same game however the time is cut" passes for a frame-rate-dependent World, because the case only cuts time in binary fractions on map 1
Where: `acceptance/moves.spec.luau` "the same draws and turns give the same game, however the time is cut"; Design, `World.advance` ("Comparisons use a tolerance of 1e-9 s"); Rules and mutants row "time cut any way gives the same game".
Evidence: the case's cuts are 6, 1/64, {1/32, 0.125, 0.375, 0.0625} and 0.5, and map 1's step is 0.25. Every sum is exact in floating point, so the tolerance never acts. On a scratch copy of the prototype with `local EPS = 1e-9` changed to `local EPS = 0`, all six acceptance files stay green. A probe plays one seeded 40 s game (1 and 3 snakes, seeded turns at fixed 0.25 s marks, deaths and respawns included) whole in 0.25 s chunks, then cut at 1/60, 1/30, 0.1 and {0.07, 0.013} s, and compares bodies, headings, states, lives, scores and apples. With `EPS = 0` the cut games differ from the whole game for both player counts. The unmutated prototype gives the same game at every cut. The server advances on Heartbeat, whose dt is never a binary fraction.
Critique: the criterion is the design's frame-rate independence, and it is checked only where float error can't appear. The tempting fix is to add 1/60 to the existing case's cut list. But that case compares `w.snakes` with `toEqual`, timers included, and a timer cut at 1/60 differs from the whole run by rounding (about 1e-16), so the correct implementation would fail it.
Consequences: comparing game state instead of raw timers means naming the fields that are the game: bodies, headings, states, lives, scores, turns, grow, apples, map and phase. Timers are compared within a tolerance (1e-6), if at all. The case must also cross a non-dyadic step (map 2 at 1/4.25 s, or map 5 at 0.2 s), a death wait and a Ready end, or the tolerance still never acts.
Recommendation: add a moves.spec case "real frame rates give the same game". It plays a seeded game (1 and 3 snakes, turns from a separate seeded draw at fixed 0.25 s marks, long enough for deaths and respawns, plus a game started with `World.start` on map 2 or 5) whole in 0.25 s chunks, then cut at 1/60, 1/30, 0.1 and (0.07, 0.013). It compares the fields above, with timers within 1e-6. Row: "instants within 1e-9 s are one instant" | moves :: real frame rates give the same game | EPS = 0. A scratch probe of this shape passes on the prototype and kills `EPS = 0`.
Lesson: z-design/spec-design-correspondence

### F2 [medium] "Timers fire before the step at the same instant" has no row, and no case tells the two orders apart
Where: Design, `World.advance` ("At an instant, in order: timers run out (...), then the step if one is due"); Edge cases ("timers fire before the step at the same instant"); moves.spec "a Ready snake stays put for 2 s, then moves" (accepts 1 or 2 steps "however the clock is phased").
Evidence: on a scratch copy, moving the step block of the prototype's `advance` ahead of the timer loops keeps all six files green, and F1's probe too, since both runs use the same order. Under that order, a snake whose Ready ends on a step instant waits for the next step. On map 1 the two always coincide: the first Ready ends with the 8th step, and a respawn's Ready ends with the 14th step after a death (a death on a step, then 1.5 s and 2 s). So under that order every Ready on map 1 lasts 2.25 s, not the game design's 2 s.
Critique: the Ready case was written to accept both orders, so the rule the Design states is free.
Consequences: none beyond the case and its row.
Recommendation: add a case: `World.new(1, d)`, then `World.advance(w, 2, d)`. The snake must be alive with its head one tile along its heading, because the Ready and the 8th step end together at 2.0 s on map 1. Row: "timers before the step at one instant" | moves :: a Ready snake moves on the step its Ready ends | the step run before the timers. Verified on a scratch copy: it passes on the prototype and kills the reordered `advance`.
Lesson: z-design/spec-design-correspondence

### F3 [medium] What counts as solid is pinned for Ready, alive and dying snakes, but not for an out snake's body or for the tiles `World.safest` must avoid
Where: Design, "A step" item 3 ("The board after the step is every moved body plus every Ready snake's body"); the prep choice "The free tile farthest from every head" ("the 4 body tiles free (no wall, snake or apple)"); deaths.spec's respawn cases; play.spec's consistency check.
Evidence: three mutants of the prototype keep all six files green:
- (a) An out snake's body counts as solid: the step's `elseif s.state == "ready"` becomes `"ready" or "over"`, and `occupancy` becomes `s.state ~= "dying"`. That leaves a permanent wall where the third death happened.
- (b) `World.safest` ignores Ready snakes' bodies. A respawn can then land on top of a snake standing in its Ready: two solid bodies on one tile.
- (c) `World.safest` lets apples sit under the 4 body tiles.

The respawn oracle can't see (b) or (c). In those 12 seeds the placement farthest from the other heads is never on a Ready body (which is within 3 tiles of its own head) or on one of the few apples. play.spec's consistency check would catch (b), but random play never crowds the board. The Design also never says what an out snake's body is: the `Snake` type comments only on the dying one.
Critique: (a) is the likeliest wrong implementation ("solid unless dying"). It matters most in f0212's arena, where play goes on during an out player's 10 s revive offer.
Consequences: f0213's view and f0215's revive both read whatever the Design says an out snake's body is, so the Design has to choose: kept as it died and not solid, or emptied.
Recommendation: state in the Design that an out snake's body stays as it died and is off the board (not solid; apples may land on it). Add two deaths.spec cases:
- "an out snake's body is off the board": two snakes; kill snake 1 three times with the existing `kill` helper, then set snake 2 alive at `line(side - 1, 3, "N")` and step. Snake 2 enters (side − 1, 2), a tile of the out body, and lives.
- "on a crowded board, World.safest returns an allowed placement farthest from every other head": 40 seeds of a 9×9 hand-set layout, with five other snakes placed Ready at random `placements()` spots, a dozen apples on random tiles, and snake 1 dying. Compare `World.safest(w, 1)` with the existing `placements` and `nearestHead` oracle: nil only when `placements` is empty, otherwise one of them, at the best distance. Guard that some seeds have a placement. The existing "no free placement" case already covers nil.

Rows:
- out body off the board | deaths :: an out snake's body is off the board | over bodies solid
- respawn avoids Ready snakes | deaths :: on a crowded board | Ready bodies ignored by safest
- respawn body off apples | deaths :: on a crowded board | apples ignored by safest

Both cases were verified on a scratch copy: they pass on the prototype, the out-body case kills (a), and the crowded case kills (b) and (c).
Lesson: z-design/spec-design-correspondence

### F4 [medium] A map start's "no turns, no growth" has no case, so a turn buffered before MAP CLEAR steers the snake on the next map
Where: Design, "A map start" ("placed at `layout.spawns[i]` with 4 segments, no turns, no growth"); progress.spec "then the next map starts" (checks body, state, score, lives and apples); rows P7 and P8.
Evidence: removing `s.turns = {}` from the prototype's `place` keeps all six files green. Only map starts change, because `die` already clears turns. In play, a player who taps Left, Left steering into the last apple has one turn used by the clearing step and one left over. `World.turn` refuses everything during MAP CLEAR, so the player can't cancel it, and the snake turns on its first move of the new map with no key pressed there. `grow` is the same rule. It can't be seen with apples alone, since an apple's 1 is spent on the step it is eaten, but f0214's golden apple adds 3.
Critique: `nearGoal` in every progress case sets `turns = {}`, so no case carries a turn across a map start.
Consequences: none beyond the case. The state is public, so the spec can set both fields by hand, as the neighbouring cases already do.
Recommendation: in progress.spec, after the clearing step set `w.snakes[1].turns = { "Left" }` and `w.snakes[1].grow = 2`, then advance 2 s. Expect `turns` empty and `grow` 0. After the Ready and one more step, expect the head one tile along the spawn's heading and the body 4 long. Rows:
- a map start clears turns | progress :: (that case) | `place` keeps turns
- a map start clears growth | same | `place` keeps grow
Lesson: z-design/spec-design-correspondence

### F5 [medium] One respawn costs 45 to 100 ms of server time in a 24-snake arena, and the Scalability section reports a per-tick average that hides it
Where: Design, Scalability ("E2 measured a 24-snake arena (side 79) of random play: about 0.8 ms per 1/30 s tick in Lune, respawns included"); Unknowns E2 (map 1 only); the prototype's `World.safest`.
Evidence: on a scratch copy of the prototype, one `World.safest(w, 1)` with every other snake Ready at its spawn costs, in Lune (mean of 5):

| players | map | side | cost |
|---|---|---|---|
| 24 | 1 | 79 (no walls) | 45 ms |
| 24 | 10 | 79 | 79 ms |
| 24 | 20 | 79 (277 wall tiles) | 101 ms |
| 24 | 30 | 79 | 104 ms |
| 8 | 1 to 30 | 47 | 12 to 23 ms |
| 1 | any | 20 to 24 | about 2 ms |

The candidate loop visits about 25,000 (tile, heading) pairs and builds a 7-tile table for each. For each open one it takes the minimum over every other head and every wall tile. E2's 0.8 ms is an average over 1,800 ticks: about one respawn a second, spread over 30 ticks. f0212 also joins players through `World.safest`, and snakes that die together respawn in the same tick, so several respawns can land in one tick.
Critique: a 60 Hz frame is 16.7 ms, so one respawn stalls the whole arena's server for 3 to 6 frames, a hitch every player sees. Fewer wall tries or a lower cap won't help: the cost is in the scan's inner loops.
Consequences: the fix must return the same answers, because deaths.spec's oracle pins the rule: Manhattan distance to the nearest other Ready or alive head, then Chebyshev distance to the nearest wall tile or the border, then the tie order.
Recommendation: specify the scan as two distance fields, each built once per call in O(side²):
- the Manhattan distance to the nearest other head: a 4-neighbour breadth-first pass over the whole grid from every head, ignoring obstacles, which is exactly Manhattan;
- the Chebyshev distance to the nearest wall tile or the border: an 8-neighbour pass from the wall tiles and the border ring, which is exactly Chebyshev.

Each (tile, heading) is then 7 lookups with no table built, O(side² · 4 · 7). Add an experiment E7 with a pass line: one `World.safest` on map 20 with 24 snakes under 5 ms in Lune, and one apple placement under 1 ms (`placeApple` builds a table per free tile: 6,241 at side 79). Fallback: keep the wall field per layout. The existing oracle cases stay as they are and prove the answers didn't change.

### F6 [medium] AC1 pins an answer that the design says it will put to the user only after this review
Where: Design, "The side for 8 and 16 players"; maps.spec "the side for N players" (`side(8)` is 47, `side(16)` is 65); frontmatter `design: reviewed`.
Evidence: "Which one the user meant is a product decision: it is put to them before `design: ready` (the dispatch question Q1)." The z-design step's dispatch folder has no `questions.md`, so nobody has been asked. The listed-numbers path (a table for 8 and 16) has no spec case and no row.
Critique: this is the lesson's defect: an open question in a design marked reviewed. Whatever the answer, the change it brings is made after the one review round.
Consequences:
- If the user picks the listed numbers, `Maps.side` stops being one formula. The table has to stay monotone (44 for 7, 48 for 8, 49 for 9; 63, 66, 67 around 16), and every caller gets it: the World's next-map roll, `Maps.spawns`, and f0212's arena.
- If the user picks the formula, game-design.md still lists 48 and 66 and needs the user's correction. c0183's digest spec passes on any historic version, so that edit costs nothing.
Recommendation: write Q1 to `$ZN_DISPATCH_DIR/questions.md` with both options and those costs, and stop before `design: ready`. Record the answer as a `Decided with the user` line. If the answer is the listed numbers, change maps.spec's two lines, add a row (mutant: the formula at 8 and 16) and add a monotonicity check over 1..24.
Lesson: z-design/no-open-question-in-a-reviewed-design

### F7 [medium] `experiments/mutants.py` rewrites source files in whatever checkout its command line names, and its restore doesn't survive the bound it prescribes
Where: `experiments/mutants.py` (`main`: `open(path, "w").write(...)` on `<checkout>/snake/src/shared/Logic/{Maps,World}/init.luau`, restored in `finally`); Unknowns E5.
Evidence: the script takes any directory as `sys.argv[1]` and writes each mutant into that checkout's `src/`. It ships in the issue's folder with the documented command `./zn run --time 1800 -- python3 .../mutants.py <prototype checkout>`. When the bound stops it, by SIGTERM or SIGKILL, Python doesn't run `finally`, so the mutant stays in that checkout's source. Today the main checkout has no `Logic/Maps`, so the first read fails before any write. Once f0211 lands it does, and so does every raft worktree built on it, where `git add -A` would commit a left-over mutant.
Critique: the zz-test rule is that changes happen only in throwaway fixtures under `.cache/`. The lesson's point, that a script takes no argument naming where to work, applies to file writes as much as to refs. A guard on the given path ("refuse the main checkout") doesn't hold, by the lesson's own account.
Consequences: the copy must still resolve its requires. This review ran all 71 mutants and C1 to C4 this way: a scratch home under `snake/.cache/<unique>/` with its own `.luaurc` (`"logic": "./Logic"`, `"tests": "../../tests"`), copies of `Logic/Maps`, `Logic/World` and the six specs, run as `lune run tests/run -- .cache/<unique>/specs/<file>` from `snake/`.
Recommendation: treat the prototype as a read-only source. The script copies the two modules and the item's acceptance specs into a fresh `snake/.cache/f0211-mutants-<pid>/` of the prep worktree, mutates only the copies, removes the folder when it ends, and never opens a file under any `src/` for writing.
Lesson: z-design/prep-experiments-run-in-standalone-clones

### F8 [low] A roll that never ends hangs the check, and the specs' draw accepts calls outside the 1..n contract
Where: maps.spec "the roll always ends"; `drawOf` in all six specs; row M17.
Evidence: M17 (no scan) is "killed by the timeout", the mutation runner's own 60 s limit. Under `./zn check f0211` the same implementation hangs instead of failing. `drawOf(0)` returns NaN without complaint (`s % 0`), and `free[NaN]` reads nil. So an implementation that calls `draw(#free)` on a full board passes food.spec, then errors on the server, where f0203's `Rng.int(g, 0)` is a misuse error.
Critique: a check that hangs gives the executor no failure to read, and a fake draw that is looser than the real one lets a server crash through.
Consequences: the draw bound must sit far above what any correct roll draws, including C3's extra draws.
Recommendation: in "the roll always ends", count the draws and error after 1,000,000 (the scan roll of map 8 takes a few thousand), so M17 fails on an assertion within about a second. Make `drawOf` (and `ones`) error unless n is a whole number of at least 1, as `Rng.draw` does. Row: "draws stay in 1..n" | food :: no free tile left | `draw(#free)` called on a full board.

### F9 [low] Records and text that disagree with the runs or the files
Where: Design (prep choices, Edge cases), Unknowns E5, Regression guard, Affected specs.
Evidence:
- The respawn's last tie-break is stated ("then to the lowest y, x and heading in N, E, S, W order"), but C2 reverses it and is called a correct variant, so it isn't really a rule.
- E5 says 73 mutants. The runner and the table have 71. This review re-ran all 71 on the final specs: all killed (M17 by timeout), C1 to C4 green.
- "During MAP CLEAR only its timer runs" and "while dying, the body it died with" have no rows. Letting death waits run during MAP CLEAR (a `placed` on the old map during the pause) and emptying the body at death both keep all six files green.
- Edge cases says "A full board: no apple is placed; the next death or tail frees a tile", which reads as a later top-up. Neither the Design nor the prototype ever places the missing apple, so the count stays short until the next map.
- The Regression guard's grep leaves out the Touched `snake/.tracker/architecture.md`, which `z-nile/tests/acceptance/c0183/designs.spec.luau` reads. That spec passes, by history, so `Overrides: none` is right, but it should be named.
- Affected specs says `tests/meta/architecture.spec.luau` reads these paths "without a watch line", but `snake/tests/inputs.tsv` watches `snake/.tracker/architecture.md` and `snake/src/` for it.

Recommendation:
- Say "any fixed order" for the last tie-break, or pin it with a case and drop C2.
- Correct E5's count.
- Add the two rows with their cases: an advance across MAP CLEAR with a dying snake yields no `placed` before `map`; and after a death, the dying snake's body equals its body before the step.
- Say plainly that a short apple count is not made up until the next map, or add the top-up rule and its case.
- Name c0183's spec in the Regression guard and correct the watch-line sentence.

## Lesson candidates (for the lead to harvest)
- pickman-test (or zz-test): a frame-rate-independence case cuts time at real frame times (1/60, 1/30, an irregular pair) across a non-dyadic step, a death wait and a Ready end, and compares game state rather than raw float timers. Why: f0211's case cut only in binary fractions on a 0.25 s step, so dropping the tolerance passed (F1). Check: is any cut, step or timer in the case a non-binary fraction, and would the correct implementation still pass if timers differed by rounding?
- z-design: a cost measured as an average over ticks is also measured per event (one respawn, one join, one roll) at the largest arena and the latest map. Why: E2's 0.8 ms a tick hid a 45 to 100 ms respawn (F5). Check: what does the most expensive single call cost, and how many of them can land in one tick?

Verdict: changes

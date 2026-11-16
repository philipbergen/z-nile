# Review 002: f0147 (design mode)
Inputs: prep worktree at 88901967 (f0147.md, check.sh, acceptance/*.spec.luau, experiments/*, design-review-001.md, design-refute-001.md, the game-design.md diff against origin/main, c0177.md); `./zn capture f0147` (ea88deb2, no marker); prototype `.worktree/proto-f0147` at 8d5a57f5, whose sequestered and promoted f0147 specs match the prep's byte for byte. origin/main has no `pickman/src` or `pickman/tests` commit since the prototype's base fb287730. Runs on the prototype: `../zn check f0147` 6/6; ramp 13, levels 17, hud 8, docs 2, all green; `mutants.py` M16 M17 M29 M30 M46 M47 M48 M49 M50 M26b M27b all killed; the whole pickman suite `lune run tests/run`: 1544 passed, 5 failed (see F1); my own mutants (a scratch copy of mutants.py's runner in my scratchpad; every file restored, `git status pickman/src` clean after each run).
Round-1 answers: F1 (carry fractions, the user's decision), F2, F3, F4, F5, F6, F7 and F8 hold. Each fix is in the files, and its new case kills its row's mutant. F1's fix brought in a new mechanism, the carry, and F1 and F3 below are holes in that mechanism.

### F1 [high] The fractional carry turns a promoted spec red that no Overrides line names: f0032's frame.spec, on the shipped config
Where: f0147.md Behaviour 2 ("each step a ghost covers `floor(carry + rate)` units [...] started at 0"), Regression guard `Overrides:`, E4; `pickman/tests/acceptance/f0032/frame.spec.luau:115-123`
Evidence: The whole suite on the prototype gives `1544 passed, 5 failed`. Four of the failures are docs specs that read edits the prototype's game-design.md does not carry (f0109's 2 and f0125's 2). The fifth is `FAIL tests/acceptance/f0032/frame.spec.luau :: a ghost that wraps through a tunnel, and every ghost after a reset, carry the tick of the jump` (`frame.spec:123: expected 62, got -1`). That spec builds `Session.new(classic, 1, Session.GAME_CONFIG)`, puts Blinky at (0, 14) heading W with progress 110, and expects one step to wrap it. On the ramp's level 1 the tuned tunnel rate is 30 × 0.5 × 0.7 / 1.1 = 9.545. The carry starts at 0, so the first step is `floor(9.545) = 9`, which ends at progress 119 with no wrap. Rounding gave 10, which wraps. With the carry turned off (M46's edit), the file passes 8/8. With the carry started at ½ instead of 0, it also passes 8/8, and the whole suite gives `1545 passed, 4 failed` (only the four docs failures). E4's "1541 passed, 2 failed" predates the carry (prototype commit 513a6738 came after it), and the round-1 refute re-ran only ramp, levels and f0125's speeds.spec.
Critique: The executor will hit a red promoted spec, which it may not edit, with no chore to narrow it, so it has to stop. The author's tempting fix is to add f0032/frame.spec to c0176's list. That narrows one more promoted file to the classic config, for a rule (the camera cut on a wrap) that the ramp doesn't change. The red comes only from where the carry starts.
Consequences: Starting at ½ makes each placement's first step `floor(½ + rate)`, which is `round(rate)`, today's whole-unit speed. The average stays exact, and only later steps alternate. The "0 ≤ carry < 1, started at 0" wording, ramp.spec's comments, and the reset case F3 asks for (whose observable changes with the start value) all follow from the choice.
Recommendation: start the carry at ½ on every placement (Behaviour 2, Interfaces `Ghost.carry`, game-design.md's Speeds bullet if it says how). Add a ramp.spec case: a fresh ramped ghost's first tunnel or frightened step is `round(rate)` (Blinky at progress 110 heading W into the side tunnel on the shipped level 1 wraps in one step). Add a row (mutant: the carry starts at 0) and a mutants.py entry. Then re-run the whole pickman suite on the prototype after every src change, record the count in E4, and paste the failing list. If the author keeps 0 instead, the Overrides line must name f0032/frame.spec with a chore in `depends_on`.
Lesson: z-design/rerun-skipped-checks-after-edits

### F2 [high] AC2 passes when the extra life scales with the current level instead of the run's starting level
Where: f0147.md Behaviour 7 ("the extra life comes when the score reaches `extraLifeScore × g.start`"); levels.spec "the extra life comes at 10,000 x the run's starting level"; Rules row M29
Evidence: Mutant X1, `g.score >= c.extraLifeScore * g.start` → `g.score >= c.extraLifeScore * g.level` in Game, leaves levels.spec green (`X1: SURVIVED (levels)`). The case sets `start` and `level` together (`h.start, h.level = 2, 2`) and otherwise uses a fresh game on level 1, so `start` and `level` are never different when the threshold is read. In the shipped game, X1 moves a level-1 run's extra life to 20,000 on level 2, 30,000 on level 3, and so on. That is the opposite of the user's "extra life unscaled".
Critique: `g.level` is the obvious field to reach for in Game, and the spec can't tell the two apart. AC2 says "the extra life comes at 10,000 × the starting level", and a wrong implementation passes it.
Consequences: f0148 will set `start` above 1, so the case also has to pin a start below the level. playAgain's `level = start` is already pinned (M30).
Recommendation: add to the case a run with `start = 1, level = 3`: `addScore(g, Game.points(g, 3333))` (9,999) gives no life, and `addScore(g, Game.points(g, 1))` (10,002) gives one. Also a run with `start = 2, level = 5` that gets its life at 20,000, not 50,000. Add row M51 (threshold × `g.level`) and its mutants.py entry.
Lesson: z-design/spec-design-correspondence

### F3 [medium] The carry's reset rule has no case: a carry that is never reset (and is shared across sessions) passes
Where: f0147.md Behaviour 2 ("per ghost, started at 0 when the ghosts are placed: a new level, a new run, a death"); Rules and mutants (no row)
Evidence: Mutant X4 keeps the carry in a module-level table keyed by ghost name (`CARRY[g.name]`) instead of on the ghost. That carry is never reset, and one session's ghosts shift another's. It survives ramp.spec (`X4: SURVIVED (ramp)`). The shared-per-set variant (X3) is killed, but only because the frightened case has four ghosts at a rate of x.5. The Design also doesn't say what happens to the carry when a ghost changes kind (frightened → hunting → tunnel). The prototype keeps it, and an executor has to guess.
Critique: Under X4, a step after a reset depends on whatever other sessions on the server did. That breaks "deterministic game code" (Pillar 2) and makes replays from a seed diverge, and no spec sees it.
Consequences: The observable depends on F1's start value. With a start of ½, a fresh ghost at rate 14.5 steps 15, 14, 15, …. A stale carry after an odd number of steps gives 14 first.
Recommendation: add a ramp.spec case. A ramped, active, frightened set on level 5 takes an odd number of steps, then `Ghosts.reset(set, "respawn", 5)` and again with `"level"`; re-frighten it, and the first counted step is `round(14.5) = 15` (with F1's ½ start). Add a second session interleaved with the first, so it also catches state shared across sets. Add a row (mutant X4, the carry kept outside the ghost) and its runner entry. State in Behaviour 2 that the carry is kept when a ghost changes kind, so the executor doesn't have to guess.
Lesson: z-design/spec-design-correspondence

### F4 [high] AC2 passes when a wasted pick counts toward the level
Where: f0147.md Behaviour 4 ("`finishPick` counts `member.levelPicks`"), Edge cases ("A pick wasted on the tenth (moved, hopped, caught): no count; the level goes on"); no Rules row
Evidence: Mutant X2 moves `member.levelPicks += 1` from `finishPick` to `startPick`, so every started pick counts. It leaves levels.spec green (`X2: SURVIVED (levels)`). The spec's walk (`pickOnce`, after E6) never wastes a pick, so a count taken at the start and a count taken at the finish always agree. In the shipped game, X2 makes a wasted pick (a movement key, a hop, a catch) count, so the level clears after fewer than ten finished picks.
Critique: The capture says "A finished wall pick (f0126) counts toward the level", and AC2 says "the tenth finished pick". The Design states the waste rule as an edge case, but no case checks it.
Consequences: f0126 has four ways to waste a pick (moved, hopped, caught, a pause). One wasted pick is enough to kill X2, because X2 counts at the start, whatever ends the pick.
Recommendation: add a levels.spec case on BARE, ramped. Start a pick (`PickStarted`), then waste it with a movement key: the frame's `picks` stays 0. Then nine finished picks plus one wasted pick: still level 1, `picks` 9, no `LevelCleared`. The next finished pick clears the level. Add row M52 (counted at `PickStarted`) and its runner entry.
Lesson: z-design/spec-design-correspondence

### F5 [low] Behaviour 2 says the eyes are strictly faster on every level up to 34, but they are capped at a tile from level 23
Where: f0147.md Behaviour 2 ("keeps the player (frightened or not), the hunting ghosts (tuned or not) and the eyes strictly faster on each level up to 34 (E2)"), against Behaviour 1 ("capped at a tile [...] from level 23") and ramp.spec (22 → 117, 23 and on → 120)
Evidence: The eyes are 120 on every level from 23 to 34, so they are equal on those levels, not faster.
Critique: The Design contradicts itself and its own spec.
Consequences: none.
Recommendation: say "the eyes up to level 23, then a tile a step".

### F6 [low] `Session.new`'s speed bounds loop to `ramp.top`, which `validateRamp` leaves unbounded
Where: f0147.md Behaviour 10; prototype `Session.new` (`for level = 1, if c.ramp then c.ramp.top else Levels.COUNT`) and `checkLevelSpeeds`
Evidence: `validateRamp` accepts any whole `top ≥ 1` and `step ≥ 1`. A config ramp `{ step = 1, top = 1e9 }` never trips a bound, so `Session.new` runs about 4 × 10⁹ speed computations before it returns.
Critique: The shipped value is fine. A later tuning typo hangs the server's session creation instead of failing.
Consequences: a cap needs a number. The loop only needs levels up to where the factor stops changing, which is `top` itself.
Recommendation: refuse `top` above a stated maximum in `validateRamp` (for example 1000, well above 34), with one more `bad` entry in ramp.spec's refusal case.

### F7 [low] c0177's narrowed f0125 eyes case keeps a title the shipped game no longer follows
Where: narrowings.patch, `tests/acceptance/f0125/speeds.spec.luau` "the eyes returning home keep twice level 1's player speed"; c0177.md Solution ("The eyes case: the shipped eyes equal the untuned config's")
Evidence: After the narrowing, the case asserts tuned eyes == untuned eyes, which on the ramp follow the level, not twice level 1's speed. The promoted title still states the old rule.
Critique: A later reader of the promoted spec learns a rule that game-design.md (after this prep) says is classic-only.
Consequences: none beyond c0177's text.
Recommendation: add to c0177's Solution: retitle the case "the eyes returning home are never tuned".
Lesson: z-design/restated-rules-move-together

Verdict: changes

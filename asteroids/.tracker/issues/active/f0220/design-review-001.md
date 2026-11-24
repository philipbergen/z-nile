# Review 001: f0220 (design mode)
Inputs: prep worktree `prep-asteroids-classic-rules` at a97ab4c2b9d3948768600577d57393d1df1dcdb5 plus its uncommitted prep files: `asteroids/.tracker/issues/f0220/f0220.md` (sha256 6892c70e5dfd…), `check.sh` (d7aa1e4a1435…), `acceptance/{field,ship,shots,rocks,saucers,hyperspace,lives,waves,game}.spec.luau`, `experiments/{prototype.patch (2b7c6150c483…), mutants.py, bench.luau}`, and the `asteroids/.tracker/architecture.md` diff; `./zn capture f0220` (capture commit d7714681); `asteroids/.tracker/game-design.md`; asteroids-arch, asteroids-test, pickman-arch, z-design and its feature checklist.

What I ran:
- `./zn check f0220`: 1/10 (AC10 passes; AC1 to AC9 fail on `could not resolve child component "Classic"`), as the doc says.
- From `asteroids/`: `tests/meta/architecture.spec.luau` 12/12, `tests/meta/home.spec.luau` 1/1, `tests/place/library.spec.luau` 2/2.
- `lune run z-nile/affected -- <path>` for each Touched path: prints nothing. `grep -rlF` over `pickman/tests/acceptance` and `z-nile/tests/acceptance` for `asteroids/.tracker/architecture.md` and `asteroids/src`: the only hit is `z-nile/tests/acceptance/c0183/designs.spec.luau`. It accepts any version in the file's history, so `Overrides: none` holds.
- `./zn run --time 600 -- python3 -I asteroids/.tracker/issues/f0220/experiments/mutants.py SO2 SO14 LI15 WA14 HY12 CV`: intended green, all five rows killed, CV1 to CV4 green. The E2 record holds for the rows I spot-checked.
- My own mutants, in a throwaway `git clone` under `$TMPDIR` with `prototype.patch` applied (a script outside the repository, run through `./zn run --time`). Each mutant was run against all nine acceptance specs (81 cases); the intended prototype is 81/81. The results are cited in the findings below. One control: a different Park-Miller draw mapping (`floor(state / M * n) + 1`) also stays 81/81, so the seeded cases don't depend on the prototype's exact `% n` mapping.

### F1 [high] The run's collisions and the saucer's shots are never checked across the wrap: AC1 passes with a run whose hits ignore it
Where: f0220.md Design, `Classic` steps 5 to 7 ("Field.sweep … across the wrap", "closer than the two radii"), step 6 ("the others move, wrap and age as the ship's do"); AC1 ("every body wraps, distances run the short way across the wrap"); Rules rows FI3, FI8 and SO8; `acceptance/field.spec.luau`.
Evidence: every case that proves the wrap calls `Field.delta`, `Field.distance` or `Field.sweep` directly, or moves a body without a target near an edge. Nothing checks that the run uses those functions for its hits. On the prototype, each of these mutants keeps all 81 cases green:
- R1: the ship-rock ram uses `math.sqrt((sx - r.x) ^ 2 + (sy - r.y) ^ 2)` instead of `Field.distance`.
- R2: the same for the ship-saucer ram.
- R3: the saucer-shot hit on the ship uses `Field.sweep` over a 1e9 × 1e9 field, so no wrap.
- R4: the same for the ship's shot against a rock.
- R26: the saucer's shots move without `Field.wrap` and fly off the field forever.
The cost in play: with the ship at (1020, 384) and a small rock at (6, 384) (10 apart across the edge), the rock passes through the ship. A shot fired across the edge passes through a rock that straddles it. A saucer shot that leaves the field never comes back. f0222 draws the field tiled "at true distance", so the player sees each of these happen.
Critique: AC1's "every body wraps, distances run the short way" can be passed by a wrong implementation. The specs hand the values to `Field` instead of going through the run, which reads them. The tempting fix is one cross-edge case for the ram only, which leaves R2, R3, R4 and R26 alive.
Consequences: none beyond the new rows and cases. The cases use hand-set state, as their neighbours do, and the prototype already passes them.
Recommendation: add run-level cases (in `field.spec.luau`, or in each owner's spec), all on a `quiet()` run with still bodies:
- (a) Ship at (1020, 384), small rock at (6, 384): `{ "RockHit", "ShipDestroyed" }`, `by = "ship"`, cause `"rock"`. Add a vertical twin: ship (512, 2), rock (512, 760).
- (b) Ship at (1020, 384), small saucer at (8, 384): `{ "SaucerHit", "ShipDestroyed" }`, cause `"saucer"`.
- (c) Ship at (6, 384), saucer shot at (1016, 384) with `vx = 6` (14 away at the start, 8 after the move): `{ "ShipDestroyed" }`, cause `"saucershot"`.
- (d) A ship's shot at (1018, 100) with `vx = 8`, small rock at (10, 100): `RockHit`, `by = "shot"`.
- (e) Add a saucer shot to "wraps every body on the field": at (1022, 700) with `vx = 6` it is at (4, 700) after one step.
Add rows FI11 to FI15 with mutants R1, R2, R3, R4 and R26, add those mutants to `mutants.py`, and rerun E2.
Lesson: zz-test/kill-mutants-where-the-value-is-built

### F2 [medium] Five rules the Design states about the tick have no row, and their mutants survive
Where: f0220.md Design, "One tick while playing, in this order (the order is a rule; the cases named in the Rules table pin each part)": step 1 ("Respawn; it acts this tick"), step 4 ("A saucer that appears does not move or fire that tick"; "once it is at least its kind's fireTicks and the ship is on the field, it fires"), steps 5 to 7. Edge cases: "the ship's shots before the saucer's shots and the collisions (a shot that breaks the rock you are about to ram scores it, though its pieces may still catch you)".
Evidence: each of these mutants keeps all 81 cases green on the prototype:
- R5b: the collisions (step 7) run before the ship's shots, with the saucer's shots still first.
- R5c: the saucer's shots (step 6) run before the ship's (step 5).
- R16: a respawned ship acts only from the next tick.
- R18: an appearing saucer also moves, and may fire, on its appear tick.
- R12: the saucer holds fire while the ship is protected. A protected ship is "on the field", so the Design says it fires.
Not one row of the table covers "ship's shots before collisions" or "ship's shots before saucer shots". The one ordering case in this area, `lives :: loses the ship once a tick`, pins step 6 before step 7 only. (R5, which moves the collisions ahead of both shot steps, dies on that case alone.)
Critique: the Design's own claim that the table pins each part of the order is false for these five. Each changes what the player sees. Under R5b, a shot that should save you from the rock is ignored and you lose a life. Under R5c, the extra life a shot earns comes after the saucer shot that takes your last ship, so the run ends when it should play on. Under R16, the respawn swallows a press.
Consequences: none new. Each is one hand-set case of the kind the neighbouring cases already use.
Recommendation: add these cases, rows and mutants, then rerun E2:
- R5b: ship at the centre at rest, a large rock still at (557, 384) (45 away, so overlapping: 45 < 52), and a ship's shot at (557, 384) with `vx = 0.1`. Expect `{ "RockHit" }` with `by = "shot"` and lives 3: the two mediums are 45 away, and 45 > 32.
- R5c: `lives = 1`, `score = 9990`, a large rock at (300, 100) with a shot at (259, 100), `vx = 2`, and a saucer shot at (497, 384), `vx = 6`. Expect `{ "RockHit", "ExtraLife", "ShipDestroyed" }`, phase `"playing"`, lives 1.
- R16: step the respawn tick with `{ fire = true }` and expect `{ "Respawn", "Fire" }`.
- R18: on the 900th tick, `g.saucer.x == 0` and `g.saucer.travelled == 0`.
- R12: `protect = 50`, a large saucer with `fireElapsed = 59`; one step gives `SaucerFire`.
Lesson: z-design/spec-design-correspondence

### F3 [medium] What protection does across a hyperspace jump is contradictory in the Design and unpinned
Where: f0220.md Prep choices, "A loss" ("its protection lasts 120 ticks ("2 s") … a protected ship flies, fires and can jump"). Step 1: "On the field: `protect` drops by one if above 0. In hyperspace: `timer` drops by one", and its parenthetical "protection covers 120 ticks from the respawn's". game-design.md: "protected for 2 s".
Evidence: step 1 counts `protect` down only on the field, so the clock stops while the ship is away. A ship that jumps 20 ticks after its respawn comes back with `protect = 100` and stays protected 150 ticks after the respawn. That contradicts "120 ticks from the respawn's" and "2 s". No case covers protection across a jump. All three of these mutants keep all 81 cases green on the prototype:
- R6: `protect` counts down in hyperspace too.
- R7: a jump ends protection.
- R22: protection also saves the ship from the re-entry explosion.
The Design implies it does not: protection "covers rocks, the saucer and its shots".
Critique: two readings fit the text, and a third (R7) is a common implementation. They play differently: a protected ship can either jump and come back onto a rock unharmed, or not. Whichever the executor picks, f0222's flicker shows it for a time nobody decided.
Consequences: protection that counts down while the ship is away changes the prototype's step 1. A protected re-entry onto a rock then passes through it while `protect > 0`, which needs a case. The re-entry explosion's exemption from protection needs saying, and a case.
Recommendation: choose the reading that keeps the product decision ("protected for 2 s"): `protect` drops every tick the ship is not lost, on the field or in hyperspace. Say in step 1 that the re-entry roll ignores protection, and mark both (prep). Then add cases:
- (a) A jump 20 ticks after a respawn re-enters with `protect == 70`.
- (b) A protected re-entry onto a small rock leaves the rock whole and the lives unchanged.
- (c) With odds 1, a protected re-entry still explodes.
Add rows for R6 (now the intended behaviour, so its mutant is "the protect clock stops in hyperspace"), R7 and R22, and rerun E2. If the author prefers the clock to stop, keep step 1 but delete "120 ticks from the respawn's", state that a jump extends protection, and pin it with case (a) expecting 100.
Lesson: zz-test/seed-every-enumerated-case (protection × ship state is a pair of sets the run walks together, and only "alive" was seeded)

### F4 [medium] Every split case shoots a rock at rest, so pieces that inherit their parent's velocity pass
Where: f0220.md Prep choices, Rocks ("every new rock (a wave's and a split's pieces) gets a drawn heading and a speed drawn from 8 steps of its size's range"); `rocks.spec.luau` (every case's parent has `vx = 0, vy = 0`); rows RO9 to RO11.
Evidence: mutant R8 (in `Rocks.split`, add the parent's `vx, vy` to each piece) keeps all 81 cases green. That is the arcade-like variant an executor is likely to write. A medium from a large moving at 1.5 then flies at up to 3.75, outside its 1 to 2.25 range, and the pieces of a moving rock all drift the parent's way.
Critique: "a speed from its size's range" is a rule whose wrong value is hidden by the fixture's zero velocity.
Consequences: none.
Recommendation: in "gives each piece its own drawn heading and a speed from its size's range", give the parents `vx = 1.5, vy = -0.5` for half the seeds (or add a separate moving-parent loop) and keep the same range checks. Add row RO20 ("a piece's speed is its own, whatever its parent's") with mutant R8, and rerun E2.
Lesson: zz-test/pin-call-site-arguments

### F5 [medium] The two-player path the Design promises is not shown to work: the per-ship rules live only in `Classic`, and no correct variant has the shape of f0221's change
Where: f0220.md Solution ("f0221 builds the two-player game from the same leaves"); Maintainability ("f0221 builds the two-player run on the leaves and a config without changing the solo tables … The correct variants of E2 … keep every promoted spec green"); E2's CV1 to CV4. f0221's capture: "Two ships share one field … own scores, lives and revives; no friendly fire by default, ships bounce; a lone survivor plays on".
Evidence: the leaves (`Field`, `Ship`, `Rocks`, `Saucers`) hold flight, rock splits and saucer motion. Everything f0221 needs per ship lives inside `Classic.step` and `Game`'s top-level fields, and all nine promoted specs read and write those fields (`g.ship`, `g.shipState`, `g.timer`, `g.protect`, `g.lives`, `g.score`, `g.nextExtra`, `g.shots`). That covers the ship's life (alive, hyperspace, dead), the clocks, the respawn wait for a clear centre, protection, the jump and its roll, the shot list and its limit, extra lives, the loss and the "one loss a tick" rule. The four CVs only add a field. None steps a second ship with its own score and lives. So f0221 can either rewrite the same per-ship rules in a second composer (two copies of the respawn, protection, hyperspace and extra-life rules that must agree) or restructure `Game` (an override chore against most of f0220's promoted cases). The Design claims neither cost exists.
Critique: the asteroids-arch checklist asks for scalability "for one player or two", and Maintainability asks where the next similar thing plugs in. The answer here is a promise that the CVs don't test. The tempting fix is another additive CV, which still isn't f0221's change.
Consequences: extracting the per-ship rules adds a feature: its folder, a unit spec (AC10), deps edges, an architecture.md row, Touched modules, about 100 more lines in `size:`, `mutants.py` anchors moved into the new file, and an E2 rerun. It also has to decide which rules stay run-wide (the saucer's fire hold and aim, the wave clock, the clear-centre test) and which are per ship.
Recommendation: decide the path now and record it in Maintainability. Two ways close this:
- **(a) Preferred.** A per-ship leaf, for example `Pilot` (`Pilot -> Field`, `Pilot -> Ship`, `Classic -> Pilot`). It holds the ship, `shipState`, `timer`, `protect`, `shots`, `lives`, `score` and `nextExtra`, with functions over a table that has those fields: the clock, the input, the loss, the respawn and the award. `Classic`'s `Game` stays a superset of those fields and passes `g` itself, so every promoted case's `g.ship`, `g.lives` and `g.score` is unchanged. f0221 then calls the same functions for each of its two pilots. Add a CV of f0221's shape: a second pilot table stepped by the same functions on the same field, with every case still green.
- **(b)** State that f0221 writes its own composer, list the `Classic` rules it must duplicate, and accept that f0221's prep pins them again.
Either one is a decision the Design then states. Leaving the promise unproven is not.
Lesson: z-design/mutation-runner-runs-correct-variants

### F6 [low] The ram and clear-centre boundaries are not pinned, though whole-number positions make them exact
Where: step 7 ("closer than the two radii added up"); step 1 ("at least its radius + `clearRadius` from the field's centre"); `rocks :: touches the ship …` (51.9 and 52.1); `lives :: waits until …` (119 / 121, 89 / 91, 99 / 101).
Evidence: R9 (ram at `<=`) and R10 (centre clear only at `>`) keep all 81 cases green. Every case sits 0.1 to 1 off the boundary, never on it.
Critique: "touching is not reaching" is pinned for `Field.sweep` (FI10) but not for the ram or the clear centre, though the Design uses the same words for them.
Consequences: none.
Recommendation: add a large rock at exactly (564, 384) (52 away, no ram) and a large rock exactly 120 from the centre (the respawn comes). Add rows RO21 and LI22 with R9 and R10.
Lesson: zz-test/refusals-tested-on-both-sides

### F7 [low] The run erases where the ship was lost on the same tick, and `ShipDestroyed` doesn't say where
Where: "A loss" ("the ship lost at the centre"); the Classic bullet "A lost ship's `ship` is `Ship.new` at the centre"; the events table (`ShipDestroyed`: `cause`, `lives`); Maintainability ("The events are the one channel f0222 renders and sounds from, so a new effect needs no new state").
Evidence: on the loss tick `g.ship` is already at (512, 384). For a hyperspace explosion the re-entry spot is gone too: it appeared only in the `Hyperspace` event 30 ticks earlier. The camera sits in the cockpit (game-design.md), so to show the explosion where it happened, or to hold the camera there for the 2 s wait, f0222's adapter must cache last tick's position. That branching belongs in Logic (pickman-arch rule 3).
Critique: the table allows a later issue to add fields (CV1 shows extra fields are safe), so this is cheap to defer. But the sentence "a new effect needs no new state" is untrue for the commonest effect.
Consequences: a new field, so a row and a case: the `FIELDS` entry in `game.spec.luau` gains `x`, `y`.
Recommendation: give `ShipDestroyed` `x, y` (the ship's position before the reset; for cause `"hyperspace"`, the re-entry spot). Pin it in `lives :: waits 120 ticks after a loss …` (a ram at (300, 200) gives `x = 300, y = 200`) and in the hyperspace explosion case. Add a row with the mutant "the loss reports the centre".

Candidate lessons (for the lead to judge; none written here):
- zz-test/kill-mutants-where-the-value-is-built could gain a note: when a run composes a geometry leaf (a wrapping field), every rule of the leaf the run relies on (wrap, short-way distance) needs a case through each of the run's consumers (each collision kind, each mover), not only through the leaf. Check: for each call the composer makes into the leaf, does a case put its inputs where the leaf's property changes the answer (across the edge)?

Verdict: changes

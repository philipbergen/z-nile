# Review 001: f0203 (design mode)
Inputs: prep commit d5743cb7e16f4320903ca3f2455de4a2e1825f76 (branch prep-input-and-look-cores): `arcade/.tracker/issues/f0203/f0203.md`, `check.sh`, `acceptance/{rng,pad,touch,look,games,place}.spec.luau`, `experiments/E1-pickman-streams.luau`, `experiments/E2-mutants.py`; `./zn capture f0203`; `./zn check f0203` (1/7 pass: AC6 green, the rest fail on missing modules or on place.spec's first case); `./zn promote-check f0203` (only missing-module errors); `lune run z-nile/affected` for every Touched path (prints nothing); `grep -rlF` of the Touched paths over every `tests/acceptance`; pickman's `Pad`, `Touch`, `View`, `Ghosts/Rng`, `Picks`, `Blaster`, `client/Camera.luau`, `client/Controls.luau`; the snake, invaders and asteroids game designs; `arcade/.tracker/architecture.md`; c0204, f0213, f0218, f0222.

Scope (item 11): the title, Problem and Non-goals match the capture word for word, and the Solution adds a paragraph under the captured comment. Outcome 1 (the four cores move into arcade as copies) has a Design and AC1 to AC4 and AC7. Outcome 2 ("every game supports keyboard, gamepad and touch for every feature ... from these cores") is the subject of F1 and F2.

### F1 [high] The rule that delivers outcome 2 to the game issues has no acceptance criterion
Where: f0203.md, Design, "Every game on every input" ("The rule, added to `arcade/.tracker/architecture.md` by the executor"); Implementation step 5; Acceptance criteria AC1 to AC7; `check.sh`.
Evidence: the Design says this issue "delivers the cores those controls are built from, proves they are enough, and writes the rule where those issues read it". No spec or `check.sh` line reads the new section. AC6's `tests/meta/architecture.spec` reads only the ```` ```deps ```` block, and it passes today with no features at all (`./zn check f0203`: `PASS AC6`). An executor who skips step 5, or who writes the section after `## Allowed dependencies` or without the rule bullet, passes all seven criteria.
Critique: the rule is the only way outcome 2's "every game ... every feature" reaches f0213, f0218 and f0222, so it is a captured outcome with no Checked criterion. The author will be tempted to pin the whole verbatim body with a text match.
Consequences: once a whole-body pin is promoted, every later edit to that section (a game adding a tuning field, another core joining) needs an Overrides chore. The descriptive paragraph is exactly what later issues will refine.
Recommendation: add a case, either in `games.spec` under AC5 or as a new `docs.spec` with its own AC8 line in `check.sh`. It reads `.tracker/architecture.md` and asserts three things:
- a `## Input and look cores (f0203)` heading exists, before `## Allowed dependencies`;
- the section holds the "Every game builds its input from these cores ... a key, a gamepad input and a touch control" bullet;
- it holds the "Game Logic never requires them" bullet.

Pin only those rule sentences, not the paragraph. The case fails on today's file. Add a Rules and mutants row for "section written after `## Allowed dependencies`" and one for "the every-input bullet left out", and run both.
Lesson: z-design/spec-design-correspondence; zz-test/criterion-fails-on-todays-file

### F2 [high] `games.spec`'s table does not match the designs it says it quotes, and AC5 passes when a feature is keyboard-only
Where: `acceptance/games.spec.luau` (the GAMES table and its header comment "The tables quote ... snake's, invaders' and asteroids' game designs"); Design, "The proof (AC5, games.spec)".
Evidence:
- **Asteroids.** `asteroids/.tracker/game-design.md:13` says "Touch: ROTATE LEFT and RIGHT on the left, THRUST, FIRE and HYPER on the right" and names no touch look. The table nevertheless gives asteroids `right = "look"`, and `context()` puts all five buttons at x 10 to 350, which is the left half.
- **Snake.** `snake/.tracker/game-design.md:18` gives look to the arrow keys only. The table encodes snake as `arrowsLook = true, lookStick = false, left = "none", right = "none"`, and the spec passes. That is a game whose look action has a key but no gamepad input and no touch control. The rule this issue writes ("every action it has gets a key, a gamepad input and a touch control") forbids exactly that, yet AC5, "every game's controls are built from the cores on keyboard, gamepad and touch", is green with it.
- **Steer modes.** The `steer = "turns" | "held"` field changes only the case's name: both modes run the same assertions.

Critique: the spec does two things it can't do. For asteroids it makes a product choice: the touch look is a prep decision, while game-design.md is binding (z-design step 2). For snake it accepts the gap the outcome forbids. Either way, the AC that is meant to prove outcome 2 doesn't check outcome 2. The tempting fix, giving snake `lookStick = true, right = "look"` too, is a second invented decision.
Consequences: these gaps sit in binding game designs, and each game's controls are a captured Non-goal (f0213, f0218, f0222). f0213's capture lists "every input: A/D, the arrows to look, Space to boost; gamepad; touch LEFT, RIGHT and BOOST", with no look on gamepad or touch. If f0203 decides the gaps, f0213 and f0222 inherit decisions nobody recorded. If it ignores them, the rule f0203 writes is broken on the day it lands.
Recommendation: rebuild the table as a matrix per game. For each feature the game's design names (snake: turn, boost, look; invaders: move, fire; asteroids: rotate, thrust, fire, hyper, look; pickman: its Platforms, Gamepad and Keys lines), list keyboard, gamepad and touch. Each cell is one of two things:
- **Quoted:** the design's input, driven through its core. A key needs no core; a stick is `Pad.steer` on that game's axes; a look stick is `Pad.look` into `Look.turn`; a button is press and release; a half is swipe or look.
- **`undecided: <issue>`:** snake's look on gamepad and on touch (f0213), and asteroids' look on touch (f0222).

Assert three things:
- every quoted cell works through the cores;
- every undecided cell's capability works through the core path that would serve it (`Pad.look` into `Look.turn`; a `"look"` half into `Look.mouse`), without choosing it for the game;
- no feature is missing a cell.

Make the "held" mode assert something "turns" does not (for example, that `Steer.held` stays set across several frames of a held tilt). Fix the comment so it says which cells are quoted, and place asteroids' buttons as its design says. Also list the undecided cells in the Design, and in the architecture.md section (F1) as "open per game", so the f0213 and f0222 preps read them. Add a Rules and mutants row: a cell dropped from the matrix is caught by the "no feature missing a cell" assertion. If the author believes f0203 must close the gaps itself, that is a question for the user (`questions.md`), not a prep choice.
Lesson: z-design/prep-choices-marked-and-checked

### F3 [high] `E2-mutants.py` rewrites source files in whatever checkout runs it, and its run line is unbounded
Where: `experiments/E2-mutants.py` (`path = f"src/shared/Logic/{feat}/init.luau"`, `open(path, "w").write(src.replace(old, new))`, header "Run from arcade/: python3 -I ..."); Unknowns & experiments, E2 ("written in `arcade/src/shared/Logic/` for prep and deleted before the prep commit").
Evidence: the script writes each mutant into `src/shared/Logic/<F>/init.luau`, relative to its working directory, and restores the file in `finally`. During prep that file was an untracked prototype inside the prep worktree, which is itself a protected worktree of the shared repository (zz-test, "Protected").
- **After execution.** Once the executor has written the real cores, anyone who re-runs E2 rewrites tracked source 58 times. A code reviewer spot-running doubtful rows is invited to do exactly that by zz-review item 0.
- **On a kill.** A SIGKILL between the write and the restore (the dispatcher's timeout, `./zn run`'s limit) leaves a mutant in the real file, and the next `git add -A` commits it.
- **Unbounded.** The documented run line is a bare `python3`, not `./zn run --time` (AGENTS.md, Processes; zz-review item 12). The document doesn't say that E1, E2 or E3 ran bounded.

Critique: zz-review item 9 counts any script in the raft that writes the repository outside a `.cache` fixture as high. The tempting fix is a guard that refuses a tracked file. The lesson says a guard on a given path is not enough: the real main checkout looks like a clone.
Consequences: the clone needs something to apply, so the prototype has to exist as a patch (F4).
Recommendation: make E2 build its own scratch repository: `git clone --no-hardlinks <top> "$(mktemp -d)/repo"`, apply `experiments/prototype.patch`, run every mutant there, and remove the clone at the end. Give it no argument that names where to work. Change the header's run line to `./zn run --time 3600 -- python3 -I arcade/.tracker/issues/f0203/experiments/E2-mutants.py` (from the top, with the script finding its own clone). Record in Unknowns that E1 to E3 run through `./zn run`.
Lesson: z-design/prep-experiments-run-in-standalone-clones

### F4 [medium] The prototype was deleted, so the 58 `run` rows and E3 can't be checked or re-run
Where: Unknowns & experiments, E2 and E3; every Rules and mutants row marked `run`; `experiments/`.
Evidence: there is no `experiments/prototype.patch`. E2's anchors (`"local r = math.abs(x)\n"`, `"taken = taken or same(f, button, side)"`, `"if button ~= nil or use ~= \"none\" then"`) match only the deleted text, so neither the review nor the executor can confirm that any mutant dies, or that the specs pass and type-check against the design's exported types.
- **Type check.** `./zn promote-check f0203` on this commit shows only missing-module type errors. That includes `pad.spec.luau(160,3)` and `rng.spec.luau(86,3)`, "Expression list has 1 value, but 2 are required", and with the prototype gone I can't confirm those disappear once the types are real.
- **Untestable rule.** Rows such as T13, which the record says needed a spec change to kill, are exactly the ones a reviewer should spot-run.

Recommendation: commit the prototype as `experiments/prototype.patch` against the prep's base and record that base sha. Re-run E2 in its clone (F3), and `./zn promote-check f0203` with the patch applied, after every spec edit this round makes. Update E2's and E3's recorded counts.
Lesson: z-design/prove-specs-pass-on-a-prototype

### F5 [medium] Horizontal fold: an engaged stick on the other side, short of `on`, keeps holding the old side
Where: Design, Pad, "`steer`, `"horizontal"`"; `pad.spec` "a horizontal fold reads the x tilt alone".
Evidence: the Design says that once engaged, `|x| < off` releases and `|x| >= on` on the other side changes at once. It says nothing about a reading on the other side with `off <= |x| < on`. Take a stick held "left" that reads x = +0.5, from a flick past the centre between two frames. It isn't released (0.5 >= 0.4) and doesn't change side (0.5 < 0.6), so by pickman's "anything else keeps the sector" `Steer.held` stays "left" while the stick points right. The Design says "Invaders and Asteroids: `Steer.held` is the held move or rotate", so the cannon keeps moving left, or the ship keeps rotating left, while the player pushes right, until the tilt reaches 0.6. No case pins this reading.
Critique: the band is harmless for pickman's one-shot sectors and wrong for a held state. The tempting fix, "change sides at `off`", removes the hysteresis on the far side.
Consequences: the two axis modes then treat the in-between band differently. That is deliberate (one is one-shot, the other held) and has to be said, so c0204 doesn't "unify" them.
Recommendation: specify it. In `"horizontal"`, an engaged stick reading on the other side of 0 releases (nothing sent) while `|x| < on`, and changes side when `|x| >= on`. Add a `pad.spec` case: held left, then x = 0.5 gives held nil and nothing sent, then x = 0.6 gives "right". Add a mutant row for "keeps the held side" and run it.

### F6 [medium] `Pad.look` returns NaN for a stick at rest under a tuning that `tune` accepts
Where: Design, Pad, "`look`"; `pad.spec` "invert flips the pitch alone, and a tuning's rates and dead zone ...".
Evidence: `tune` accepts `lookDead = 0` (lookDead runs from 0 to 1, exclusive of 1), and the spec itself builds `Pad.tune({ lookYaw = 6, lookPitch = 1, lookDead = 0 })`. At x = y = 0, r = 0 is not `< lookDead`, so a = 0 and `dyaw = -a * (x / r) * ...` gives `-0 * NaN`, which is NaN. A resting stick is the most common reading. This contradicts the Design's Usability line: "a misuse ... is an error with the function's name, not a NaN later".
Recommendation: specify that `r <= lookDead` gives 0, 0. For any `lookDead > 0` this is the same as pickman's rule, because a = 0 at `r = lookDead`. Add the case `Pad.look(0, 0, 0.1, Pad.tune({ lookDead = 0 }))` giving 0, 0, and a mutant row for `<` instead of `<=`.

### F7 [medium] Refusals the Design states have no case or mutant, and one refusal is missing
Where: Design, Rng ("Refusals"), Pad ("`tune` refuses"), Look ("`tune` refuses"); the `bads` lists in `pad.spec` and `look.spec`, and `rng.spec` "new refuses ..."; Rules and mutants (only R8, P11 and L14 cover refusals).
Evidence:
- `Pad.tune`: "a non-boolean invert" has no case, so a `tune` without that check passes. "lookDead outside 0..1" is tested only at 1, so a mutant that checks only `< 1` survives `lookDead = -0.1`.
- `Look.tune`: "any non-finite value" is never tested for `turnSeconds = math.huge`. "Not above 0" doesn't catch it, and with it `rate = 0`, so the spring and the eased turn never move.
- `Rng.new`, the mix: only the range is stated ("a mix outside 0..2^21-1"). A mix of 1.5 gives a fractional state, and then `Rng.int` returns non-whole draws, which breaks "int draws whole numbers". The multiplier's wholeness is pinned only by the spec's 16807.5 case, not by the Design's text.
- `Rng.new`, `mix = 0`: it is accepted, and then every seed gives the same sequence.
- `Rng.new`, the other refusals (multiplier 1, mix -1 and 2^21, offset 0.5 and M): they have cases but no mutant rows.

Recommendation: state "whole" for the multiplier and the mix. Decide `mix = 0` and write it down: refusing it, so the mix runs from 1 to 2^21-1, keeps every pickman stream valid. Add to the `bads` lists `{ invert = 1 }`, `{ lookDead = -0.1 }`, `{ turnSeconds = math.huge }`, `{ mix = 1.5 }` and `{ mix = 0 }`. Add one mutant row per refusal sentence and run them on the prototype (F4).
Lesson: z-design/prove-specs-pass-on-a-prototype (the R0044 design review 1 F3 note: one mutant per sentence that states a refusal or a bound)

### F8 [medium] What the Design promises c0204 isn't where c0204 will read it, and the list of differences from pickman is incomplete
Where: Design, Rng ("c0204's to note"); Pad ("c0204 compares with a tolerance"); Look ("pickman's `View.look` would carry the NaN"); `pickman/.tracker/issues/c0204/c0204.md:22` ("no behaviour change").
Evidence: c0204 is `new` and undesigned. It says "Pickman uses arcade's Rng, Pad, Touch and Look cores; its own copies of the generic parts are deleted; no behaviour change", and mentions none of the differences f0203 names. Several differences aren't named anywhere:
- **Touch, begin.** A begin at a non-finite point is classified by pickman's `Touch.zone` as the look zone (`NaN < width / 2` is false, so "look") and tracked. Arcade drops it.
- **Touch, look move.** A look move to a NaN point makes pickman send a NaN look step. Arcade drops it.
- **Touch, buttons.** Pickman's buttons produce one effect on begin; arcade's produce press on begin and release on end, so c0204 must map press.
- **`Look.ease`.** It ignores a bad `dt`, while pickman's `Camera.luau` passes any `dt` to `approachYaw`.

Recommendation: add one "Differences from pickman's copies" list to the Design, each entry giving pickman's behaviour, arcade's and why. Put the same list, short, in the architecture.md section the executor adds, since c0204's Problem cites that file. F1's case may pin the list's heading.
Lesson: z-design/quote-other-preps-before-promising

### F9 [low] The Regression guard's override grep searched for `arcade/src` only
Where: Regression guard, "Override check".
Evidence: `grep -rlF -e arcade/.tracker/architecture.md */tests/acceptance` lists `z-nile/tests/acceptance/c0183/designs.spec.luau`, which pins that file's SHA-256 and is not named. It stays green because it accepts any version of the file in history (today's file already hashes to `7bc2219e…`, not the pinned `01cc4877…`), so `Overrides: none` is still right.
Recommendation: name it in the Regression guard, with why the step-5 edit keeps it green.

### F10 [low] Invaders' FIRE disc is hit-tested as a square
Where: Design, Touch (`Button = { name, rect }`); `invaders/.tracker/game-design.md:11` ("a FIRE disc on the right").
Evidence: a touch in the corners of the disc's bounding square, outside the drawn disc, presses FIRE.
Recommendation: state that the hit area is the button's rectangle, so the adapter sizes the disc's square to at least `MIN_TARGET`, or add an optional `round: boolean?` that hit-tests the inscribed circle, with a case. Say which, so f0218 doesn't have to ask.

### F11 [low] A vacuous assertion in `rng.spec`
Where: `rng.spec` "the same seed and stream give the same sequence; another seed gives another".
Evidence: `t.expect(draws(Rng.new(9), 50, 40) == draws(Rng.new(10), 50, 40)).toBe(false)` compares two fresh tables by identity, so it is always false, whatever `Rng` does. The `same < 10` count that follows does the real work.
Recommendation: drop the identity line.

### F12 [low] The "no key map" case doesn't look at Touch's or Rng's tables
Where: `games.spec` "the cores hold no key map".
Evidence: it checks only `Pad.BUTTONS`, `Pad.action`, `Look.KEYS` and `Look.action`. A Touch core that kept pickman's HUD layout (`Touch.buttons`, `snapRect`, `fireRect`), which the Design says stays pickman's, passes.
Recommendation: also assert that `Touch.buttons`, `Touch.snapRect`, `Touch.hopRect`, `Touch.fireRect`, `Touch.pickRect` and `Touch.blocks` are nil.

## Lesson candidates (for the lead)
- pickman-test (or arcade-arch): when a fold's state is read as a held value (a held move or rotate) rather than as a one-shot event, pin what it holds in every region of the input on both sides of its hysteresis band. A band that is harmless for one-shot sectors holds the opposite direction for a held one (F5). Check: for each fold mode used as held, is there a case for each region (released, engaged with the same side short of `on`, the other side short of `on`, the other side past `on`)?

Verdict: changes

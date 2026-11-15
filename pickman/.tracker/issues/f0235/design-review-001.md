# Review 001: f0235 (design mode)
Inputs: prep worktree `prep-pickman-power-pills-visible-jumping` at 9c6c8b4ba9e32b01da1215ec179efdaf86c632be plus the uncommitted f0235 folder: `f0235.md` (sha256 75a75c67beda…), `check.sh` (fef7c8e29015…), `acceptance/{beacon,rule,pellets,place,docs}.spec.luau`, `experiments/{E1-pellet-sight.luau,prototype.patch (b657e1171426…),game-design.patch,mutants.py}`; `./zn capture f0235` (bfd0d41e); f0234's prep (`.worktree/prep-pickman-jump-arc-on-start`, HEAD 40365ef0 "tracker: prep f0234 …", `f0234.md`, `acceptance/`, `experiments/prototype.patch` (1c3f18f2c64e…)); c0228's prep (no overlap, below); origin/main's sequestered specs of d0149 and f0143.

How I ran things: every run is in a standalone clone of this worktree at `/tmp/f0235-review-probe/clone` (the f0235 folder copied in, f0235's `prototype.patch` and `game-design.patch` applied), through `./zn run --time <s> -- …`. The behavioural probe I cite as "the probe" is a throwaway spec in that clone. It loads the real Camera source on camera-pad's stub engine, with a `CFrame.new` that records its `y` and sets `Position`. It pushes a snapshot, runs one render step, then prints and compares `Camera.eye()` with the recorded `y`, standing and then at a hop's top (`Camera.hopped(snap.tick - Hop.TICKS / 2)`). On the f0235 prototype alone, the baseline is green: place 4/4, pellets 11/11, beacon 6/6, rule 7/7, docs 3/3, f0101/place 5/5, and the probe prints `standing: drawn 4 Camera.eye() 4`, `hop top: drawn 18 Camera.eye() 18 elevated true`. `./zn promote-check f0235` on the clone: OK.

Scope (item 11): the title, Problem, Non-goals and Solution match the capture word for word. Each captured outcome has a Design and a Checked criterion: beacons while jumping (AC2, AC3), only the remaining pellets (AC2, AC3), seen over the walls (AC1), f0234's wait (AC2, AC3 and OC2), and distinct from f0236 (AC6). F1 shows that the f0234 outcome, and in fact every beacon, is lost on the tree where f0234 lands too.

### F1 [high] f0235 and the in-flight f0234 rewrite the same render-step line: the merge is clean, Camera.eye() is nil forever, every f0235 check stays green, and f0234's sequestered camera.spec goes 6/6 → 0/6
Where: `f0235.md` Design, "Why the drawn eye" ("f0234 needs nothing from f0235, but its wait must raise the eye through `Camera`'s render-step `camera.CFrame` write … Once f0235 is done, its promoted `place.spec` keeps that wiring"); Adapters, `Camera.luau` (module-level `eye`, read back with `eye = camera.CFrame.Position.Y`); `depends_on: []`; Regression guard, "Overrides: none".
Evidence:
- f0234's prep has committed its design (40365ef0, `design: reviewed`). `f0234.md:49` designs the same line: "The render step's eye becomes `local eye = View.SCALE.eyeHeight + Hop.rise(hopped, shown, hopTicks) + Hop.held(readyEnd, shown)` and `camera.CFrame = CFrame.new(x, eye, z) * ...`". Its `prototype.patch` does exactly that. `f0234.md:67` says "f0235 … can read the same `Hop.held(readyEnd, shown)` (or the eye sum) that Camera computes; this issue promises nothing to it beyond these two public functions." So no f0234 document carries f0235's constraint, and f0235's document never mentions f0234's prep or prototype.
- In the clone I ran `git apply --index` with f0234's prototype, committed it, then ran `git apply -3` with f0235's `prototype.patch`. The output was "Applied patch to 'pickman/src/client/Camera.luau' cleanly" (and to the other four files too), with 0 conflict markers. The merged `Camera.luau` has `28: local eye: number? = nil -- … (f0235)`, then `151: local eye = View.SCALE.eyeHeight + Hop.rise(hopped, shown, hopTicks) + Hop.held(readyEnd, shown)`, then `155: eye = camera.CFrame.Position.Y`. The read-back assigns the render step's own local, so the module-level `eye` is never set.
- On that merged tree, every f0235 spec passes: `place.spec` 4/4, `pellets.spec` 11/11, `rule.spec` 7/7 and `docs.spec` 3/3. `f0101/place.spec` also passes (5/5). The probe prints `standing: drawn 4 Camera.eye() nil` and fails. No beacon would ever show, in a hop or in f0234's wait.
- On the same tree, f0234's sequestered `acceptance/camera.spec.luau` fails all six cases (`[string "Camera"]:155: attempt to index nil with 'Y'`). On f0234's prototype alone it passes 6/6. Its stub `CFrame.new` returns a frame with no `Position`: the same failure f0235 fixed in camera-pad by editing that spec, which f0234's executor may not do. Renaming f0235's variable doesn't help. I tried `drawnEye = camera.CFrame.Position.Y` after f0234's write, and f0234's camera.spec still failed 6 of 6, on the same error.
- So whichever issue lands second turns the other's spec red (f0234's spec is sequestered, and promoted once f0234 is done), and f0235 names no override, no order and no chore.
- The same reading of f0235 alone: f0234's own line as a variant (`local eye = <the sum>` before the write) passes f0235's `place.spec` 4/4 and f0101 5/5, and the probe returns nil.
Critique: both of the design's promises fail on the one tree they are about. The read-back makes f0234 need something from f0235 (a `Position` in its stub). The promoted `place.spec` does not keep the wiring either, because the shadow passes it. The captured outcome "including the elevated wait of f0234", and every hop's beacon, would be lost with every check green. The tempting fix is a rename.
Consequences: a rename removes the shadow but keeps the `Position` read, which still turns f0234's camera.spec 0/6, as run above. And the next `local` of the getter's name passes AC4 again (F2).
Recommendation:
1. Stop reading back `camera.CFrame.Position`. The eye the camera draws becomes one module-level value that the one CFrame write is built from. At module level: `local eye: number? = nil`. In the render step: `eye = View.SCALE.eyeHeight + Hop.rise(hopped, shown, hopTicks)`, then `camera.CFrame = CFrame.new(x, eye :: number, z) * …`. `Camera.eye()` returns `eye`. This is "the eye sum that Camera computes" that `f0234.md:67` already offers. It keeps the literal that f0101's and f0126's promoted pins and f0143's sequestered pin read (`f0234.md:49`).
   - I ran this on the merged tree: f0234's `local` dropped, its `+ Hop.held(readyEnd, shown)` kept in the sum, f0235's read-back line removed, and camera-pad's stub reverted to main's. Results: f0234 camera.spec 6/6, f0234 place.spec 3/3, `f0101/place.spec` 5/5 and `tests/place/camera-pad.spec.luau` 5/5 with no stub change. The probe gives `Camera.eye()` = 4 standing and 18 at a hop's top.
2. Replace AC4's read-back text case with F2's behavioural cases. They go red on the shadow in either landing order:
   - f0235 first: they are promoted when f0235 is done, so f0234's executor must drop its `local`.
   - f0234 first: f0235's executor must drop it.
3. Drop the camera-pad stub change: remove it from the Design, Touched modules, Implementation step 3 and the Regression guard. Rewrite "Why the drawn eye": the eye is the value the one CFrame write is built from, and anything that raises the camera adds to that sum.
4. Record the pair:
   - In Unknowns, as an experiment: run both landing orders on a merged prototype (f0235 three-way on f0234's prototype, and f0234's on f0235's), each with both issues' acceptance specs plus `f0101/place` and camera-pad. Name f0234 in the Regression guard.
   - The constraint itself ("Camera's render-step eye is the module-level `eye` that `Camera.eye` returns; f0234 adds `Hop.held` to that sum and declares no local of that name") goes into f0234's document as a dated line, through its prep. If that can't be done from this prep, put it under `## Open to the human` so the user rules before either is readied.
   - Once both orders are green, no `depends_on` is needed. If one is wanted, make it f0235 → f0234 (f0234 makes the wait), and have the readying lead rerun both issues' specs on the merged prototype before `ready` (z-design lesson design-the-execution-window).
5. Add Rules rows for three mutants, each killed by F2's cases: S1 (a `local` of the getter's name in the render step), S2 (the rise stored instead of the eye), and M20.
Lesson: z-design/quote-other-preps-before-promising (also z-design/mutation-runner-runs-correct-variants: f0234's actual prototype diff was never run against f0235's specs as a correct variant)

### F2 [high] AC4's Camera.eye case is a source-text match that wrong implementations pass; no spec runs the real Camera to see that Camera.eye() is the drawn eye
Where: `acceptance/place.spec.luau:50` ("Camera.eye returns the variable the render step reads back from camera.CFrame after drawing"); Rules row M20; AC4 ("`Camera.eye` returns the eye read back … set nowhere else").
Evidence:
- On the f0235 prototype alone, mutant S2 `eye = camera.CFrame.Position.Y - View.SCALE.eyeHeight` (the rise, not the eye) passes `place.spec` 4/4. The pattern `eye%s*=%s*camera%.CFrame%.Position%.Y` matches the line's prefix, and the probe prints `Camera.eye() 0` standing.
- With the rise stored, `View.elevated` is false for any rise in (5, 9]. Beacons would then show for only part of the airborne span, against AC2's "exactly where the rise clears the walls".
- S1 (F1) also passes 4/4, because the "set once" counter skips every line that starts with `local`.
- `pellets.spec` hands PelletView a stub getter, so no spec ever calls the real `Camera.eye`.
Critique: AC4 states a behaviour (what `Camera.eye()` returns), and its check reads spellings. The tempting fix is a tighter pattern (anchor the line end, forbid `local eye`). The next spelling gets past it: `(camera.CFrame.Position.Y)`, a helper, or another name for the local.
Consequences: the case needs a Camera rig. `tests/place/camera-pad.spec.luau` already loads the real Camera on a stub engine. With F1's design, its `CFrame.new` only has to record `y`, so no `Position` is needed.
Recommendation: under AC4, in `acceptance/place.spec.luau` or a new `acceptance/camera.spec.luau` named by AC4's `check`, add cases that run the real Camera on that rig, with `CFrame.new` recording each `y`:
- (a) Before any snapshot, `Camera.eye()` is nil after a render step.
- (b) After a snapshot and one step, it equals the recorded `y`, which is `View.SCALE.eyeHeight`.
- (c) With `Camera.hopped(snap.tick - Hop.TICKS / 2)`, it equals the recorded `y` (`eyeHeight + Hop.RISE`), and `View.elevated` of it is true.
- (d) With `Camera.hopTicks(Hop.LONG_TICKS)`, at a shown tick where the rise is between 5 and 9, it equals the recorded `y` and is elevated (kills S2).

Keep a text case only for what behaviour can't observe, if anything is left. Rows: S1, S2 and M20 against these cases, run on the prototype.
Lesson: zz-test/source-pins-name-what-the-design-names

### F3 [medium] "Beacons do not pulse" has no row, and a beacon that pulses into a 3-stud cube passes AC3
Where: Design, "What the player sees" ("Beacons do not pulse (the pellets under them still do)"); Rules and mutants (no row); `acceptance/pellets.spec.luau:262`, the only case that reads a beacon's `Size`, and it runs before any render step.
Evidence: mutant S3 adds `table.insert(h.power, beacon)` after `h.beacons[i] = beacon` in the prototype's `build`, and `pellets.spec` stays 11/11. Each frame the pulse then sets the beacon's `Size` to `Vector3.one * (View.PELLET.power * pulse)`: a cube of at most 3 studs around the pellet's centre, under the wall tops. It is lit at a jump's top, and no beacon is ever seen over the walls.
Critique: AC3 says PelletView builds the beacons at `View.beacon`. Nothing pins that the render handler leaves their geometry alone after that, which is the one thing that makes them visible. The rule is in the Design and has no row (item 0).
Consequences: the size must be read after a render step, because only the handler resizes. The pulse case already moves the clock, so the check fits there.
Recommendation: in `acceptance/pellets.spec.luau:394` ("the pellets stay as the code says … still pulse"), after the half-pulse render at TOP, assert that each Beacon's `Size` and `Position` still equal `View.beacon`'s (width, height, width and centre) and that it is lit. Add the row "beacons keep `View.beacon`'s size and place every frame (they do not pulse)" with mutant S3, run.

### F4 [medium] A hop across a remaining power pellet takes the eye through its lit beacon, and the Design never says what the player sees then
Where: Design, Edge cases (eye heights and pellet states only) and Usability ("so a ghost behind it stays visible").
Evidence (computed from the repo's numbers):
- While airborne the player keeps moving and eats nothing: game-design's Spy hop says "pellets passed over are not eaten", and `Session.luau:673` has `if e.kind == "Entered" and not airborne`. So a power pellet that is hopped over stays present, and its beacon stays lit.
- The camera follows the interpolated tile pose along the corridor's centre line, so it passes straight through the pillar's axis. The eye is between 9 and 18 studs, inside a pillar that runs from 3 to 20.
- Player speed is about 30 studs/s: `Movement.DEFAULT_CONFIG.speed` 30 of `Movement.UNITS` 120 per tile, at `Session.STEP_RATE` 15. At that speed the eye goes from 4 to 1.5 studs of the axis in about 83 ms (5 frames at 60 fps).
- At 2.5 studs the near face spans 2·atan(1.5/2.5) ≈ 62° of the width and almost all of the 80° height. That is a 70%-opaque neon band over the middle of the screen, which vanishes once the eye is inside (a part's faces are not drawn from within).
- The 667 ms airborne window covers 2.5 tiles, so any hop that starts within about two tiles of a power pellet, down its corridor, passes through it. That is the corridor where the ghost being jumped over usually is.
Critique: a visible flash on an ordinary move, which no edge case, AC or OC names. The tempting fix is a thinner or more transparent beacon. That trades away AC1's seen-across-the-maze size, and the flash stays.
Consequences: hiding a beacon near the eye has knock-on effects:
- PelletView needs the eye's horizontal place: a second getter, `Camera.pose` (the shape of `DangerHud.start(Camera.pose)`).
- It needs a radius.
- The key must change when the near beacon changes, which happens every frame while the pose moves (4 distance checks).
- Main's call and AC4's pattern (`PelletView%.start%(%s*Camera%.eye%s*%)`) change.
Recommendation: decide this and pin it. The option that holds up:
- Add `View.BEACON.clear` (tiles, since `Camera.pose` is in tile coordinates; e.g. 0.5).
- Change the signature to `View.beacons(slots, present, elevated, pose: View.Pose?)`: a slot within `clear` of the pose is false, and a nil pose means no slot is near.
- `PelletView.start(eye, pose)`, with Main passing `Camera.pose`, and the key extended by the near slot's index.

The cases this needs:
- `rule.spec`: elevated with the pose on a power slot's tile → that slot is false and the other three are true. At `clear` + ε → true. A nil pose → as today.
- `pellets.spec`: a hop along the corridor hides that beacon, then relights it.
- `place.spec`: Main passes `Camera.pose`.
- Rules rows: radius ignored, and `<=` against `<` at the edge.
- The game-design bullet says it.

If the author would rather keep the pass-through, it becomes a **(prep)** choice: the bullet states it, and OC1 gains the step "hop along a corridor through a power pellet", so the user judges it rather than the executor stumbling on it.

### F5 [low] The Affected specs list is missing 20 specs, because the selector prints nothing for a directory path
Where: `f0235.md` Affected specs (the "221 specs" command and its output).
Evidence:
- `lune run z-nile/affected -- pickman/src/shared/Logic/View` prints 0 lines and exits 0. So do `pickman/src/client` and `pickman/src/shared/Logic/Hop`. With `pickman/src/shared/Logic/View/init.luau` it prints 239 lines.
- The design's command, with the directory, prints 221 lines. The same command with the file path prints 241. `comm` of the two lists gives the 20 missing:
  - `f0109/{colors,docs,place}`
  - `f0126/{adapters,boons,classic,closed,controls,eaten,ghosts,maze,parts,pick,picks,touch,views}`
  - `f0146/{controls,flow,pad,place}`

  That includes `f0126/views.spec` and `f0109/place.spec`, both of which the Regression guard names.
- I ran every spec in f0109, f0126, f0146 and c0170, plus `f0054/docs`, on the prototype: 190 passed, 0 failed. So no Override is missing: E3's full run stands.
Recommendation: rerun the selector with the Touched path `pickman/src/shared/Logic/View/init.luau` and paste its 241 lines.

### F6 [low] The game-design bullet misstates E1, and constrains f0236 beyond its capture
Where: `experiments/game-design.patch`.
Evidence: "from a jump's top it shows across the whole maze where the pellet itself shows from about 5% of the tiles". E1 counted 56 of 1,196 **(tile, power pellet) pairs** (4.6%), not tiles. Also, "f0236's glow over the regular pellets must differ from it in colour and form" goes further than the captured Non-goal ("must be clearly distinct from this indicator"). Both pellet kinds share one `COLOR`, which the beacon now takes, so "in colour" denies f0236 a glow in its own pellets' colour. No f0236 document carries that constraint.
Recommendation: write "from about 5% of the (tile, power pellet) pairs" and "f0236's glow over the regular pellets must be clearly distinct from it". `docs.spec` needs only "f0236", so no spec changes.

### F7 [low] architecture.md's View row is not updated
Where: Touched modules; Implementation step 2.
Evidence: `pickman/.tracker/architecture.md:30` lists each feature's View additions ("… pellet placement and pulse (R0015, f0030) …"). f0235 adds `BEACON`, `beacon`, `elevated` and `beacons`, and nothing mentions the row. f0234's prototype updates its Hop row in the same way.
Recommendation: add "the power pellets' beacons and the raised-eye rule (f0235)" to the View row, and add `pickman/.tracker/architecture.md` to Touched modules and to step 2.

### F8 [low] The experiments' bounded commands are not recorded
Where: Unknowns & experiments, E1 and E4; the header of `experiments/mutants.py`.
Evidence: E1 records only "Method: `experiments/E1-pellet-sight.luau`", and E4 only "run from `pickman/`". The header of `mutants.py` says "Run from pickman/ on the prototype branch only", with no `./zn run`. Each of its subprocesses has a 300 s timeout, but the script itself is not bounded (item 12).
Recommendation: record each experiment's command as it was run (`./zn run --time <s> -- lune run …`, `./zn run --time <s> -- python3 experiments/mutants.py`), and put the same command in the header of `mutants.py`.

Checked and clean:
- Repository safety: the specs only read (`place.load` builds into `.cache`, `docs.spec` reads `game-design.md`), and `check.sh` only runs the spec runner.
- Architecture: Logic stays pure, there is no new dependency edge (View already requires Pellets), and the server is untouched.
- Other in-flight work: c0228's prep (Main and View, walls only) stubs PelletView with a fallback that takes any argument. d0149's and f0143's sequestered Camera cases never render, and f0143's text pins keep holding.
- The two game-design bullets (f0234's before Glows, f0235's after) merge with no conflict (`git merge-file`).
- The other 21 mutants are killed, as E4 records. I spot-ran none of them again, beyond the baseline above.

Candidate lessons and captures for the lead (from this reviewer):
- Note for z-design/quote-other-preps-before-promising: a clean `git apply -3` of two preps' prototypes does not show they are compatible. f0234's and f0235's prototypes merged with no conflict into a local that shadowed f0235's module-level `eye`. Check: on the three-way merge, do both issues' acceptance specs pass, and does a behavioural case observe the shared value?
- Capture candidate (z-nile): `lune run z-nile/affected -- <directory>` prints nothing and exits 0 (`pickman/src/client`, `pickman/src/shared/Logic/View`), although the Touched modules template allows "file or directory prefix". Rule: the selector expands a directory prefix to its files, or refuses it. Check: does `lune run z-nile/affected -- pickman/src/client` select the specs of every file under it?

Verdict: changes

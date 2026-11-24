# Review 001: c0228 (design mode)
Inputs: prep branch `prep-walls-built-once-per-maze` at 25911b5a with its staged files (`c0228.md`, `check.sh`, `acceptance/runs.spec.luau`, `acceptance/walls.spec.luau`, `experiments/prototype.patch`, `experiments/mutants.py`); origin/main d239b5c6; `./zn capture c0228` (capture 8b754034, confirmed, no marker); `lune run z-nile/affected --` on each Touched source path; in-flight worktrees `proto-f0234`, `prep-pickman-jump-arc-on-start` (f0234), `prep-pickman-power-pills-visible-jumping` (f0235).
Spot-runs: a scratch clone under `$TMPDIR` (`origin` removed) at d239b5c6 with `prototype.patch` applied and the two specs copied in. BASE is green (runs 4/4, walls 7/7). The author's `mutants.py BASE M14 M6 M8 C1`, run through `./zn run`, reproduces the record: M14, M6 and M8 are killed on their named cases, and BASE and C1 are green. The two mutants and the correct variant below were run the same way.

Scope fidelity holds. Title and Problem are unchanged. The Solution keeps the captured idea and adds detail. Each captured outcome has a Checked criterion: the first frame builds once (AC2), and f0126's "once per walls key" and f0109's `wallColorOf` pin stay green (AC3). The design's main premise holds: M14 is killed by f0126 views.spec, so the skip has to live in MazeView. Overrides `none` holds too: the prototype keeps every promoted spec I ran green.

### F1 [high] The skip leaves f0126's only check that a wall drawn under the flash comes out lit with nothing to test, so a rewall that draws marked walls gold under the flash passes every check
Where: c0228.md Design, "Colours of skipped walls", and Regression guard; `pickman/tests/acceptance/f0126/views.spec.luau:594` (`mv.rewall(model, classic, { at(2, 2) }) -- rebuilt while lit: lit`); `acceptance/walls.spec.luau` cases "a rewall to other walls draws them" (unlit and inedible only) and "a rewall to the drawn walls keeps their lit and edible colours" (it reaches only skips).
Evidence: mutant L, in MazeView's local `walls`, replaces `part(model, "MarkedWall", wallColorOf(model, true), size, center)` with `part(model, "MarkedWall", rgb(View.wallColor(false, model:GetAttribute("Edible") == true, true)), size, center)`. f0109's `"Wall", wallColorOf(` pin still matches.
- **On origin/main d239b5c6**, L is killed: `FAIL tests/acceptance/f0126/views.spec.luau :: MazeView's flash lights the marked walls with the rest, and gives them back their gold`. That case's last rewall goes to the walls already drawn, while lit, and on main it redraws them.
- **On the prototype**, that rewall is skipped. L then passes all 14 specs that read MazeView: c0228 runs and walls, f0126 views, adapters and parts, f0109 place and colors, c0164 walls, tests/place/main-walls, f0014, f0101 and f0031 place, and unit View view and marks. 98 passed, 0 failed.
- **No other case reaches it.** walls.spec's only rewall to other walls runs unlit (BLUE/GOLD), and its lit case rewalls only to the same walls, which is a skip. A redraw while edible is still checked (f0126 views.spec:687); a redraw while lit no longer is.
- **The game reaches this path.** Main calls `MazeView.rewall` before `MazeView.flash` in the same handler. On a frame whose walls change while the model is still `Lit`, the new parts are coloured right here.

Critique: AC3 is the issue's promise that f0126's checks still hold. It still passes, but one of its cases no longer reaches the code it was there to check. A delivery of this chore that also miscolours a redrawn marked wall passes `check.sh` whole. The Design cites f0126's case for skipped walls, which it now covers, but nothing covers walls that are drawn. The tempting fix is one `mv.flash(model, true)` before one rewall in "a rewall to other walls draws them".
Consequences: View.wallColor has four states (unlit, edible, lit, lit and edible, where the flash wins), and the draw path picks a colour in each. A lit case catches L only if the new walls include a newly marked run. The edible-only draw path is still checked by f0126:687, so only the lit states need new coverage. The f0109 text pin constrains Wall's colour call, not MarkedWall's, so this case is MarkedWall's only check.
Recommendation:
- Run the rewall-to-other-walls cases in walls.spec under every model state, in "a rewall to other walls draws them" or in a new case "a rewall to other walls draws them in the model's lit and edible colours":
  - unlit: BLUE/GOLD;
  - edible: GREEN/GOLD;
  - lit: LIT/LIT;
  - lit and edible: LIT/LIT.
- In each state, give the new walls a mark that wasn't there before, and assert `drawnAs` plus `wallsMade` (drawn whole, once).
- Add the Rules row "walls a rewall draws take the model's lit and edible colours" with mutant L. Record L in E3 as `run`: killed by the new case, and surviving without it, as above.
- Rewrite the Regression guard: f0126's "rebuilt while lit" now reaches a skip, and the new walls.spec case covers the redraw.
Lesson: none existing fits. Candidate for the lead (z-design): "When a change makes an existing path a no-op for some inputs (a skip, a cache hit), list the promoted cases whose inputs now take the no-op and move what each one checked on the old path into a new case." Check: "Which promoted case used to reach the code this skip bypasses, and does a mutant of that code that main kills still die on the prototype?"

### F2 [medium] Nothing checks that each model keeps its own record of drawn walls: one module-wide key passes every spec, and with it a second model built with the last walls drawn gets no walls
Where: c0228.md Design, MazeView bullet "`local drawn: { [Model]: string } = setmetatable(...)` … keyed by the maze model"; AC2 ("the walls a model has drawn"); Rules and mutants (no row).
Evidence: mutant G replaces the `drawn` table with `local drawnKey: string? = nil` and the skip with `if drawnKey == key then return end drawnKey = key`. It passes the same 14 specs, 98/98. Every MazeView case loads a fresh module and builds one model, and walls.spec's Main harness builds one maze. Under G, a `MazeView.build(m, marked)` whose walls equal the last walls drawn on any model returns a maze with its doors and floor and no walls. Main builds a second model only on a new `frame.maze`, and only "classic" exists, so G is unreachable today. But the Design's Maintainability says a new layout "needs nothing here", and the Design states the rule per model.
Critique: the Design states a rule that no case can fail (z-design/spec-design-correspondence). The tempting fix is a case that builds two models.
Consequences: the per-model rule has two sides. A second model's build draws its walls whole. A rewall on model A doesn't change what model B is recorded as having drawn. The weak-key collection can't be observed under Lune; don't try to check garbage collection, since the Design already reasons that a lost entry only redraws.
Recommendation: add a walls.spec case, "each maze model keeps its own drawn walls":
1. In one `mazeView()`, build A and B with equal walls and marks. Both must be `drawnAs` whole, and `wallsMade` must count `2 * #runs`.
2. Rewall A to other walls: drawn, once.
3. Rewall B to its own walls: no part made.
4. Rewall B to A's new walls: drawn whole, once.

Add a Rules row "what a model has drawn is that model's own" with mutant G, run in E3.
Lesson: z-design/spec-design-correspondence

### F3 [low] Existing work says no in-flight worktree changes Main or View, but the f0234 and f0235 preps both do
Where: c0228.md Existing work, "In-flight worktrees: … none whose branch changes … `Main.client.luau` or `src/shared/Logic/View`".
Evidence:
- **f0234** (status preparing): `proto-f0234`'s working tree adds `Camera.ready(frame.play, frame.tick)` to Main's frame handler after `Camera.hopTicks(...)`, and adds `View.readyEnd` to View.
- **f0235**: its Touched modules list `Main.client.luau` (`PelletView.start(Camera.eye)`), `PelletView.luau` and `View`.
- **Run together:** with proto-f0234's Main, View, Camera and Hop diff applied on c0228's prototype, c0228 runs and walls, f0126 views and adapters, and main-walls are green (32/32). f0234's held, ready and camera specs are green too; its place case on game-design.md and architecture.md failed only because I didn't copy those documents.
- **f0235** has no prototype yet. walls.spec's PelletView stub answers `start` with a no-op, and `PelletView.build` still gets the layout (f0235's `Pellets.slots(m)` needs it). So I found no conflict.

Critique: the result is harmless, but the record is wrong. The executor won't know that two preps share Main's handler with this chore, and neither will they.
Recommendation: under Existing work, name f0234 and f0235, what each changes in Main and View, and the combined run. Add f0234's Main line as a correct variant C3 in `mutants.py`: insert `\tCamera.ready(frame.play, frame.tick)\n` after `\tCamera.hopTicks(frame.hopTicks)\n`, and run it against walls, views and adapters. Tell both preps that c0228 changes Main's build line and adds `MazeView.build`'s optional `marked`.
Lesson: z-design/quote-other-preps-before-promising; z-design/mutation-runner-runs-correct-variants

### F4 [low] Three statements in the document are wrong or rest on an unstated fact
Where: c0228.md Affected specs; Scalability; Non-goals (first bullet) together with the Main block in the Design.
Evidence:
- **(a) The selector skips main-walls.** The Affected specs section places `pickman/tests/place/main-walls.spec.luau` among the selector's output, and E2 says it "ran all of them". `lune run z-nile/affected --` on each of the three Touched paths (239 unique specs) doesn't list it. Its watch file `tests/place/main-walls.watch.txt` names only `tests/lib` files, although the spec reads Main from the built place. So step 4's "affected gate" doesn't run it. AC3 does (E5's check run), so this issue is still covered.
- **(b) View.walls runs twice.** Scalability says "`View.walls` is computed once, as now". On a maze's first frame it runs twice, with `View.runsKey` twice: once for the build's draw and once for the rewall's key.
- **(c) The floor depends on a fact the Design doesn't state.** Non-goals says MazeView.build draws the floor "as it does now", but build now gets `View.frameMaze(frame)`. The floor's size is `View.bounds(m)`, whose tunnel margins depend on `wraps()` over the first row and column. It is equal only because picks mark interior walls only (`Picks/init.luau:44`; game-design "not on the maze's outer edge").

Critique: (c) is a hidden coupling. If a later pick rule allows edge walls, the floor would depend on whether the client's first frame had holes.
Recommendation:
- Correct (a) and (b).
- State (c)'s dependency next to the build call, and check it: one assertion in "Main builds every wall once …" that the Floor part's Size equals `mv.build(classic)`'s Floor Size, with holes opened.
- For (a), the selector gap (main-walls.watch.txt lacks `src/client/Main.client.luau`, so `--affected` skips the spec on any Main change) is pre-existing. The lead should capture it as an issue.

### F5 [low] `mutants.py`'s usage tells the executor to make a hardlinked clone whose origin is the real repository, unlike zz-test's method, and gives no time limit
Where: `experiments/mutants.py` header (`git clone <repo> "$(mktemp -d)/repo"`); E3 ("through `./zn run --time`", no limit); Unknowns ("Nothing is left for the executor's Phase 1 beyond re-running E2 and E3").
Evidence: zz-test SKILL.md:144 gives `git clone --no-hardlinks . "$(mktemp -d)/repo"`. The header's clone shares object inodes with the real `.git` and keeps `origin` pointing at it. I found no write path to the real repository. The script does no git writes, restores each file in `finally`, and refuses clones outside the temp folder or sharing this git directory. The specs it runs are fenced. So this is low.
Recommendation: make the header `git clone --no-hardlinks <repo> "$(mktemp -d)/repo" && git -C <clone> remote remove origin`, and give the command with its limit (`./zn run --time 900 -- python3 -I <path>/mutants.py <clone>`). Make the script refuse a clone that has any remote (`git -C <clone> remote` not empty), which keeps it off the real repository whatever the caller did.

Verdict: changes

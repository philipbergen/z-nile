# Review 002: R0035 (design mode)
Inputs: prep-ghost-hunter-tools at 827e990 (`git diff 6db85f4..HEAD` as the fix delta, plus the whole raft: R0035.md, R0035/check.sh, experiments, f0100/f0101/f0102/f0104 documents, check.sh files and acceptance specs, the f0110 stub); tracker/game-design.md, tracker/architecture.md; design-review-001.md and design-refute-001.md; R0012's documents and acceptance specs in prep-mobile-controls (b531210, read only). The prototype worktree proto-ghost-hunter-tools at c08d562: its `src/` and `tests/unit` diff is identical to `experiments/prototype.patch`, and its acceptance copies (`tracker/issues/<id>/acceptance`, `tests/acceptance/<id>`) are identical to the prep worktree's. There: the 19 acceptance specs pass (140 cases); `scripts/check.sh --full` passes (1963 cases, 282 files, GATE PASSED, no REPOSITORY CHANGED); `mutants.py` runs all 94 mutants, all KILLED by an assertion; I also ran one mutant of my own (below). The proto worktree was left with `git status` clean.
Dropped from review-001: F1, F2, F3, F4, F5, F6, F7, F8, F9

Rulings on design-refute-001:
- F1 (fixed, holds). The mouse line `look = View.look(look, delta.X, delta.Y)` stays verbatim, and the arrow look runs after it (`steer = View.steer(steer, look, arrows, dt)`, `look = steer.look`). R0012's f0028 `place.spec` pins `not mouseHeld and not lookedThisFrame` before `View.look(look, delta`, before `lookedThisFrame = false`, before `snap == nil`. f0104's pins (the mouse line before `View.steer(steer, look, arrows, dt)`, and `look = steer.look`) can both hold on one merged Camera. R0012's `Camera.lookBy` writes `look = View.look(look, dx, dy)` between frames, which `View.steer` sees as a take-over. I checked the one way the "look differs from last frame's" test could misfire. The zero-delta mouse line re-wraps the yaw every frame, and if `wrap` weren't idempotent, every spring would be cancelled one frame after release. Over 2,000,000 random `approachYaw` outputs, `View.look(l, 0, 0)` returned exactly the same yaw every time. I also drove Camera's exact frame order through holds and releases of every arrow pattern at four frame times, and the look always came back to 0. A reference-compare mutant (`if look ~= prev.look`) is killed by the take-over case's first assertion. Controls, Main and DangerHud also stay compatible with R0012's pins (`Controls.start(Camera.snap, …`, `View.KEYS`, `BindActionAtPriority`, no `gameProcessed`; the radar lines untouched; HudView's `DisplayOrder = 1`; the shot bars fit inside R0012's lives blocks on its phone, landscape and desktop samples).
- F2 (fixed, holds). S12 and S13 are killed by the new case (re-run).
- F3 (fixed, holds). `Frame.shot` comes from the server's spend. S14, S15 and V3 are killed (re-run). Frames are fired every step on a reliable remote, so `shot.tick == frame.tick` sees every shot.
- F4 (answered as a user decision, holds). It is recorded as (prep) in game-design, with a Non-goal for per-member streams. See F3 below about where the open question lives.
- F5, F6, F9 (fixed, hold). G17–G20 are killed (re-run).
- F7, F8 (fixed).

### F1 [medium] The shot from the pre-move tile still misses junction shots the player sees as on time: what the player sees is 1–3 steps behind the server, and a fire, unlike a turn, is not buffered
Where: f0100 Design ("The shot starts from the tile the player holds at the start of the step"); `Session.shoot` (`local from = Movement.occupied(s.maze, member.move)`); `shots.spec :: a moving player shoots from the tile it holds before this step's move`; game-design Ghost hunter tools (prep) "the shot starts from the tile the player holds before that step's move".
Evidence: Camera draws `View.interpolate(prev, snap, View.alpha(os.clock() - arrived))`, with `View.alpha(e) = e * STEP_RATE`. So the player on screen is between the previous and the latest snapshot, on average half a step behind the latest. The latest snapshot is one-way latency old, and the fire takes one-way latency to reach the server. At level 1 a step is 30 units (a quarter tile) and 67 ms of real time. At 100 ms round trip, the server's pre-move position when it takes the fire is about 0.5 + 1.5 = 2 steps (60 units) past what the player saw. Take a player who presses E with an arrow toward the side corridor when they see themselves at the junction's centre. On the server they are half a tile past it, which is exactly where `Movement.occupied` rounds to the next tile. About half of those shots hit the wall beside the corridor, and the shot is spent. At 200 ms (3.5 steps, 105 units) almost all of them miss. The junction tile is held for 4 steps (267 ms), so the window exists, but it runs a third to a half of its length ahead of what the screen shows. Turns don't have this problem because they are buffered and taken at the next tile with that exit (game-design Movement). A fire is taken on the step it arrives.
Critique: review 001 F2's fix pinned the server's order. That is one step of the offset, and it is right. But the case it was meant for, "pressed on a junction, goes up the side corridor", still fails from the player's seat on ordinary latency (pillar 3, fair and readable). The tempting fix is to send the client's rendered tile or tick with the fire. That changes the string wire (RC2, f0100's place pins), and a tile the client supplies is a cheat channel the server would have to bound anyway.
Consequences: a server-side grace, like game-design's cornering grace for turns, needs a few things.
- A short history of recent tiles in `Member` (tile, tick), cleared in `teleport`.
- A bound in ticks: a tuning constant, for example `Blaster.GRACE_TICKS = 4` (2 steps).
- A rule for when the grace applies. Only when the line from the occupied tile is blocked at once in that heading, so shots along the corridor and into an open side are unchanged.
- An answer for wraps and for a ghost on the current tile.

It is a product rule, so it goes to the user.
Recommendation: put it to the user with this prep's other questions.
- (a) Keep the pre-move tile only. Say in game-design (prep) that a side shot must be pressed about half a tile early at 100 ms of latency, and add an OC1 step on Beta (fire at a junction you see yourself on).
- (b) Add the grace: "a shot whose line from the occupied tile is blocked at once goes instead from the latest tile the player held within `GRACE_TICKS` ticks whose exit in that heading is open". If the user picks (b), add these `shots.spec` cases:
  - a player 60 units past the junction's centre (now holding the next tile) shoots up the side corridor and eats the ghost;
  - `GRACE_TICKS + 1` ticks past, the same fire hits the wall and is spent;
  - a shot along the corridor is unchanged (no grace when the line is open);
  - no grace across a death's teleport.

  Rules rows and their mutants: no grace, an unbounded grace, a grace applied when the line is open, and history kept through a teleport.

### F2 [medium] `mutants.py` defaults to the current checkout, writes mutants into its `src/`, and restores them with `git checkout --`, discarding uncommitted work
Where: `tracker/rafts/R0035/experiments/mutants.py`: `ROOT = sys.argv[1] if len(sys.argv) > 1 else "."`; `open(path, "w").write(mutated.replace(old, new))`; `subprocess.run(["git", "checkout", "--", f], cwd=ROOT)`.
Evidence: with no argument, or with `.`, the script edits the checkout it is run from. Any row whose old text matches (every row, once the raft's code is in that tree) is written into `src/…`, outside `.cache` and outside the jail. The file is then reset from the index, so any uncommitted change to that file is lost. Two cases make this likely:
- Once the raft has landed, the old texts match on `main`. A run from the main checkout writes the main checkout, which AGENTS.md says is never edited.
- In the raft's own worktree, an executor or code reviewer who reruns the mutation check against the real implementation (a natural way to audit the `run` rows) loses unstaged edits to `View`, `Session`, `Camera`, ….

No check runs this script, so neither the runner nor `repo-fence.spec` sees it. It is the only experiment script in `tracker/rafts` that runs `git checkout`.
Critique: the usage line says to use a scratch worktree, but the default and the restore method make the unsafe run the easy one. The tempting fix is a stronger comment, which leaves the default in place.
Consequences: restoring from the saved text instead of from git keeps uncommitted work. Refusing the main checkout needs a way to recognise it (`git rev-parse --git-common-dir` against `--git-dir`). Both are plain reads.
Recommendation: make ROOT a required argument. Refuse a ROOT that is the main checkout (its `--git-dir` equals its `--git-common-dir`). Restore each file by writing back the `src` text read before the mutation (in the `finally`), not with `git checkout`. Say in R0035's Experiments phase that the script is run only on a scratch worktree with the prototype committed. No spec or check changes.

### F3 [low] The questions put to the user are recorded only in a refute file, and f0100's E4 count is stale
Where: design-refute-001 F4, F7 and F9 ("the question to the user"); game-design "Open decisions" (lists only `Blaster.DROP_PERCENT` and `Levels.GHOST_TUNING`); R0035 Theme ("One new open decision: the drop chance"); f0100 Unknowns E4 ("1957 cases in 282 files") against R0035 E4 and this run ("1963 cases, 282 files").
Evidence: three things wait on the user:
- seeding the drops per session instead of per account;
- hiding the shot bars on touch until f0110;
- Inky's new colour.

game-design records the first two as (prep) defaults, which is correct, but none of the three is listed as asked. The refute file is where an answer would be looked for last.
Critique: if the user answers after the prep commit, nothing tells the executor which document changes. Inky's colour in particular is "one row if answered before execution".
Consequences: none.
Recommendation: add the three questions to game-design's Open decisions (or to the raft's Theme next to the drop chance), each with the prep default and where an answer lands (Sessions.luau and RC2 for the seed; HudView for the touch bars; `View.GHOST_COLORS` or f0109 for Inky). Correct f0100's E4 count to 1963.

Verdict: changes

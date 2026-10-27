# Review 005: R0051 (design mode)
Inputs: prep worktree at 996f445e plus its uncommitted edits (R0051.md, R0051/check.sh, harvest.md, f0110.md, f0110/check.sh, f0110/acceptance/{buttons,fold,adapters,hunt}.spec.luau, game-design.md, architecture.md, the lessons `design-the-execution-window` (edited), `check-open-defects-on-the-path`, `prep-choices-marked-and-checked`, `pickman-test/drawn-from-the-visible-root`); design-review-001 to 004 and design-refute-001 to 004; `./zn capture f0110` (f880bedb); origin/main at a198cb0b (`git log 9938c429..origin/main -- pickman z-nile`: d0151, d0149, c0150 to c0155, spends); the open PRs (#130 f0126 prep, #128 c0150 prep; #127 closed); the f0126 prep worktree's uncommitted edits; the local branch `capture-d0149-circle-answers` (0a402e56); prototype `proto-f0110` at a042afce and its CI run 40266995186.
Dropped from design-review-004: F1, F2 (both answered `fixed`; rulings below).

Rulings on design-refute-004:
- F1 fixed, with one gap. The user's order (d0151, f0110, f0126, d0149) is quoted in f0110's Problem and R0051's Theme; PR #127 is closed unmerged; d0149 on origin/main has `depends_on: [d0151, f0110]` and a decision line saying f0110 lands first as a stopgap; f0110's folder stays in `done/`. Nothing is left for a redo. The gap: the d0149 Problem line naming the chore that narrows `tests/acceptance/f0110/`, which the refutation calls "landed by a capture edit", is not on origin/main (F2).
- F2 fixed. E6 was run by the user ("Nothing responds"), the cause is its own defect d0151, and `depends_on: [d0151]` makes `./zn ready` refuse R0051 until d0151 is in `done/` (z-ready step 2; engine `… must be done first`). The scope is still the capture's: the title and the captured Problem sentence are unchanged, and both outcomes keep a Design and Checked criteria (AC1 to AC4). What the dependency itself leaves open is F1 below.

Also checked and sound:
- The two openings this round. On `proto-f0110` (restored after each run, `git status` clean): one more Logic require in Controls (`Logic/Hud`): adapters 10 passed; a non-Logic require (`Shared/Config`): 5 failed, so the stub still refuses what it should; M9 (the fire effect sends the hop): 4 failed; M13 (Main drops the fifth argument): 1 failed; an extra `pick` field in `Touch.buttons`: buttons 6 passed; `fire = hopRect`: 3 failed; `snap` dropped: 2 failed. The four specs are byte-identical to the sequestered ones (`cmp`).
- Prep tree: `./zn check f0110` gives AC1 to AC4 FAIL and AC5, AC6 PASS, as E3 says; `./zn audit` 0 errors (the R0040 warning is not this raft's); `./zn lessons --check` ok (78 lessons, 501 entries).
- f0126 and f0146 now route their additions so f0110's specs hold: f0126 sends `View.PICK_INTENT` with no new Controls require (its E8 ran f0110's sequestered files), f0146 pins entries not the map's size; neither adds a `Controls.start` argument, so adapters' `HudView%.buttons%s*%)$` pin holds. c0155 (on main) narrows f0110's button-table pin after f0110 is done and says it has nothing left to do if this prep did it, which it did.
- The new lessons (`check-open-defects-on-the-path`, the added question in `design-the-execution-window`) are lessons another raft could fail, not restated findings.

### F1 [medium] Nothing re-proves f0110's sequestered specs after d0151 changes the touch path they model, and no one can see them break until execution
Where: R0051 Order & dependencies ("After d0151, Phase 1 checks on a phone that a look drag and the snap button respond, and escalates if not"); f0110 E6 ("Once d0151 is done the executor's Phase 1 re-runs the question on a phone"); f0110 Implementation step 1; `adapters.spec.luau` `controls()` and `hudView()` stub engines.
Evidence:
- d0151 is a bare stub on origin/main. Its Solution names exactly the code these specs model: "whether `Main.client.luau` reaches `Controls.start`", "whether `UserInputService.InputBegan` delivers `UserInputType.Touch`", "whether a GUI or Roblox's own touch handling consumes the touches". Its fix is likely to change `Controls.luau`, `Main.client.luau` or `HudView.luau`, the files f0110 changes.
- `adapters.spec`'s Controls stub is closed on everything but Logic: `GetService` is `assert(services[name], name)` over ContextActionService, GuiService, ReplicatedStorage and UserInputService, and touches arrive only through `InputBegan/Changed/Ended` with `gameProcessed = false`. A d0151 fix that reads one more service (StarterGui, Players, GuiService properties), listens on `TouchStarted`, or handles touches with `gameProcessed = true` turns AC3's Controls cases red. I checked the mechanism with a non-Logic require: 5 of 10 fail. A service works the same way.
- d0151's prep can't see this. f0110's specs aren't promoted until R0051's `done`, so d0151's Overrides check (`affected` plus `grep tests/acceptance`) doesn't find them. On main they fail anyway (AC1 to AC4 are red before f0110's implementation), so running `./zn check f0110` there proves nothing.
- The executor would then see AC3 red at step 1, where red is expected, build the design, and find AC3 still red for a reason only an edit to a sequestered spec fixes: a stop and an escalation back to prep.
- The phone check in Phase 1 is also not runnable by an executing agent. It needs the user on a device, and d0151's own Observed criterion is where that answer will be recorded.
Critique: round 4's fix made d0151 a dependency, but proved the specs only against today's input path, which d0151 exists to change. This is the "do this raft's sequestered specs still pass once both have landed" question of `design-the-execution-window`, here for a dependency that lands first. The tempting fix is to open the Controls stub's `GetService` the way the require was opened. That hides only one of the ways a d0151 fix can break the stub (signals, `gameProcessed`), and a stub that answers any service with an empty table can't fake behaviour.
Consequences: a re-proof needs the prototype and someone to run it. `proto-f0110` is on origin, so it can be merged with main after d0151. If a spec must change, f0110's sequestered files change after the prep PR has landed, which is a new prep pass with a review round, not something the readying lead or the executor may do.
Recommendation:
- In R0051 Order & dependencies and f0110 E6, replace the executor's phone re-check with a pre-`ready` step for the lead who readies R0051, after d0151 is in `done/`:
  - read d0151's Verification log for its phone result (look drag and snap respond), or ask the user;
  - merge origin/main into `proto-f0110`, then re-run the four specs, E2's full gate and E4's mutants there, and record the result in E6;
  - if any of f0110's specs or its Design must change, R0051 goes back to z-design (a new review round) before `ready`.
- Keep "escalate if touch still doesn't respond" as an execution stop condition only as a backstop.
- Ask that d0151's prep (a note on d0151 through a capture edit, which the user words if it touches scope) run f0110's four sequestered specs on `proto-f0110` merged with its fix. Then a fix that breaks them is seen while d0151 can still choose another shape.
Lesson: z-design/design-the-execution-window, z-design/prove-specs-pass-on-a-prototype, z-design/instructions-runnable-where-they-run

### F2 [low] d0149's obligation to narrow `tests/acceptance/f0110/` exists only on an unpushed local branch
Where: design-refute-004 F1 ("landed by a capture edit, `tracker: scope d0149 …`"); R0051 Risks, "d0149 replaces this design" ("its prep owns a chore that narrows or removes `tests/acceptance/f0110/`").
Evidence: commit 0a402e56 "tracker: scope d0149 circle answers from the user" is on local branch `capture-d0149-circle-answers` only. `git merge-base --is-ancestor 0a402e56 origin/main` fails, and `git ls-remote origin` shows no such branch. d0149 on origin/main names neither the chore nor the circle answers.
Critique: R0051's Risks state as fact a duty that d0149's document does not yet carry. If the capture is never landed, d0149's prep would find the red f0110 specs only through its Overrides check (round 4 called that a backstop, not the record).
Consequences: none beyond landing it. The edit adds decision lines the user gave, which is what a `tracker: scope` capture is for.
Recommendation: land it (`./zn land` from that worktree) before the prep PR. Or say in R0051's Risks that it is pending, with the branch name.

### F3 [low] f0110 still says the touch pick button is d0149's, while the user has since put it in f0126, built on f0110's buttons
Where: f0110 Non-goals ("A pick button (f0126's wall pick): d0149's; `Touch.Buttons` may gain a field for it"); Regression guard ("so a PICK field (d0149) keeps it green"); R0051 Risks, the f0126 bullet.
Evidence:
- c0155 on main (captured 19:43) quotes the user's decision "PICK button after f0110": f0126 adds "a touch PICK button beside f0110's FIRE and JUMP".
- The f0126 prep worktree's current edits add AC11 ("on touch, the PICK button sits one margin left of FIRE, level with it, its size; Touch.buttons carries it") and a `pick` zone and effect.
- d0149's pending scope edit says "No pick button until f0126 is built". The three documents name three different owners.
Critique: f0110's specs already admit the field (checked above), so nothing breaks. But the f0110 and R0051 documents misstate who extends `Touch`, `HudView` and `Controls` next, and they omit c0155, the chore that will check this prep's by-field pin. An executor reading R0051's Risks would expect f0126 to touch only the pick bar and banner.
Consequences: none for the design. The owner is the user's ruling, already given.
Recommendation:
- Reword the Non-goal: the touch PICK button is f0126's, added after f0110 (user, 2026-10-25, "PICK button after f0110"), one margin left of FIRE, as a `pick` field of `Touch.Buttons` and a `pick` zone.
- Change "(d0149)" to "(f0126)" in the Regression guard.
- In R0051's Risks f0126 bullet, name the PICK button and c0155. c0155 finds the by-field pin already narrowed.
Lesson: z-design/design-the-execution-window, z-design/restated-rules-move-together

### F4 [low] E5 records no Linux run of the specs as round 4 changed them
Where: f0110 E5 (the last run recorded is 40236303256 @ dc6c8bf1); `adapters.spec.luau` and `buttons.spec.luau` changed after it (the open stub require with its `(require :: any)("@logic/" .. name)` cast, and the by-field pin); prototype commit a042afce "round 4 open specs".
Evidence: CI run 40266995186 on `proto-f0110` @ a042afce was in progress during this review. `gate (pickman)` had passed and `gate (z-nile)` was still running. E5 does not mention it.
Critique: the same gap as round 3's F2 (prove-specs-pass-on-a-prototype: each platform, re-run after a spec change), already being closed but not recorded.
Consequences: none.
Recommendation: record run 40266995186's outcome in E5 (both jobs), or the outcome of a re-run if it fails.
Lesson: z-design/prove-specs-pass-on-a-prototype

Verdict: changes

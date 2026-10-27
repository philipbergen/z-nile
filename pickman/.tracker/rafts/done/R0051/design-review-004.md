# Review 004: R0051 (design mode)
Inputs: prep worktree at 996f445e plus its uncommitted edits (R0051.md, R0051/check.sh, harvest.md, f0110.md, f0110/check.sh, f0110/acceptance/{buttons,fold,adapters,hunt}.spec.luau, game-design.md, architecture.md, the lessons `design-the-execution-window` (edited), `prep-choices-marked-and-checked` and `pickman-test/drawn-from-the-visible-root`); design-review-001 to 003 and design-refute-001 to 003; `./zn capture f0110` (f880bedb); origin/main at 9bff365d (`git log 9938c429..origin/main -- pickman z-nile`: d0149, f0126 preparing, c0150, spends only); PR #127 (`capture-touch-controls` @ eff4b96a, draft, unchanged since round 3); d0149, c0150 and f0126 on origin/main; the f0126 prototype `proto-risky-wall-picks` (uncommitted: Hop gains an optional length, Hud gains `pickProgress` and `boonBanner`); c0116 (R0050) section "Preps open on branches with the old flow"; prototype `proto-f0110` at dc6c8bf1.
Dropped from design-review-003: F1, F2 (both answered `fixed`, and both fixes hold: see below).

Rulings on design-refute-003:
- F1 fixed. The user's answer, "Land R0051 as a stopgap", is recorded as a `Decided with the user (2026-10-25)` line in f0110's Problem and in R0051's Theme, d0149's circles are a Non-goal, game-design.md's bullet names the stopgap before its **(prep)** marker, and R0051's Risks name PR #127, d0149's chore and how f0126 and c0150 meet this raft. The scope is the capture's: the title and the captured Problem sentence are unchanged, and both outcomes (fire, a jump control) keep a Design and Checked criteria (AC1 to AC4). What the documents still leave open about PR #127 and about device touch is F1 and F2 below.
- F2 fixed. E5 records run 40236303256 @ dc6c8bf1, with both gate jobs passing.

Also checked and sound:
- Prototype. f0110's four specs, f0027/28/29, f0100/01/04, `tests/unit/Touch`, `touch-adapters`, `hud-shots` and `tests/meta/architecture` on `proto-f0110`: `255 passed, 0 failed, 35 spec files`. The four specs are byte-identical to the sequestered ones (`cmp`), and `git diff --stat d8a9a9aa origin/main -- pickman/src pickman/tests` is empty, so the prototype's base is still current.
- Prep tree. `./zn check f0110`: AC1 to AC4 FAIL and AC5 and AC6 PASS, as E3 says. `./zn lessons --check`: ok (77 lessons, 498 entries). `./zn audit`: 0 errors (one warning, R0040, not this raft's).
- Old-flow landing (c0116). f0110 and R0051 both carry the stamp `preparing-badger-raging-indigo` on origin/main, so the carried move takes f0110 as an old-flow member, which needs no `grouped:` record.
- PR #127 can't merge silently in either order. It deletes `issues/f0110/{f0110.md,check.sh,spend.md}`, and this prep PR modifies two of them, so whichever lands second hits a modify/delete conflict. After `ready`, the move to `active/` turns that into a rename/delete conflict.
- f0126 and c0150. The f0110 specs press only E and Space, never count keys, and read only `Hop.INTENT` and `Hopped` on the next step. f0126's prototype only adds optional arguments to `Hop` and functions to `Hud`, and leaves `Hud.jumpButtons`, `Hud.blocks`, `Hud.shotIcons` and `Hud.radarBox` alone. So the "textual only" claim holds for what exists today.

### F1 [medium] The documents leave PR #127's redo free to delete f0110 after `done`, and d0149 carries none of the obligations this prep gives it
Where: f0110 Problem, the `Decided with the user` paragraph ("PR #127's removal of f0110 waits for that"); R0051 Risks, "d0149 replaces this design" ("it is redone after R0051 lands … d0149's prep then owns a chore that narrows or removes `tests/acceptance/f0110/`"); PR #127's body and its d0149.md.
Evidence:
- "Waits for that" can only be read as "the removal happens later". R0051 says the PR "is redone after R0051 lands" but not what the redo contains.
- PR #127, as it stands (eff4b96a, still a draft), deletes f0110's whole folder. Its d0149 line still reads `Scope decision (user, 2026-10-25): "Fold f0110 into the new defect": f0110 … is folded into this issue and removed.`
- d0149 on origin/main is a bare stub that names neither f0110's buttons nor the spec-retiring chore.
- Once R0051 is done, f0110's folder is in `done/`. Its specs are promoted under its id (zz-rules, Ids: "a done copy's specs are promoted under its id"), and its `spend.md` feeds metrics.
- `audit.luau` has no check for a raft whose member is missing (its codes: dead-raft, duplicate, id-mismatch, legacy-name, next-*, no-document, no-slug, raftless-active, registry, retired-raft, shared-number, wrong-kind). So a redo that still `git rm`s `done/f0110` lands green. It orphans `tests/acceptance/f0110/`, leaves done R0051 listing a member that no longer exists, and drops f0110's spend.
Critique: the user's decision ends the fold: f0110 is delivered, not removed. The documents still describe a removal, though, and the only record of what d0149 now owes lives in f0110 and R0051, which d0149's prep has no reason to read. The tempting fix is to add "don't delete f0110" to f0110.md. That fixes this document but not the place the redoer works: PR #127 and d0149.
Consequences: the redo rewrites the user's own scope line on d0149, and only the user may reword it. d0149's prep would find the red f0110 specs anyway, through its Overrides check (zz-review design item 4: `affected` plus `grep tests/acceptance`), so the spec-retiring chore is a backstop, not the only guard. A done item that leaves `done/` is not something the tracker models (lesson zz-rules/retire-keeps-what-readers-count).
Recommendation:
- In f0110's Problem paragraph and R0051's Risks, say what the redo of PR #127 is:
  - It keeps f0110, which is in `done/` after R0051, as the promoted specs' owner and spend record.
  - It adds the d0149 stub's Problem text with the user's request.
  - It replaces the fold's scope line with one the user words. It should say that f0110 landed as the stopgap (R0051) and that d0149 replaces its FIRE/JUMP buttons and owns a chore that narrows or removes `tests/acceptance/f0110/` (with zz-test/narrowing-pins-the-whole-file).
- Replace "waits for that" with "is redone after R0051 is done, without removing f0110".
- The lead should put the same three points as a comment on PR #127, so whoever redoes it reads them where they work.
Lesson: zz-rules/retire-keeps-what-readers-count, z-design/instructions-runnable-where-they-run

### F2 [medium] The stopgap's premise, that touch input reaches Controls on a phone, is contradicted by d0149 and has no experiment or fallback
Where: f0110 E6 ("A Frame with `Active = false` lets the touch through to `UserInputService` … Left for OC1"); R0051 Risks (no entry for it); f0110 Problem's decision line ("so touch players can shoot and hop now"); OC1.
Evidence:
- d0149 on main: "Touch controls don't work". PR #127's d0149: "on a phone the controls do not work: players on touch devices can't steer, look or play". Its Solution makes "find why today's touch controls fail (f0027 / f0028 on a real phone)" the first step.
- The new buttons go through exactly the path that report covers: `Controls.luau` `onInput` (lines 114 to 158: `UserInputService.InputBegan/Changed/Ended`, `Touch.toScreen` over `GetInsetArea(None)`, then `Touch.track`). Fire and hop are just two more effects of that one fold.
- If the cause is anywhere on that path (no touch events, wrong screen conversion, `TouchEnabled` false), FIRE and JUMP fail exactly as turn and look do. OC1 then fails, and touch players gain nothing from the stopgap.
- Round 3 F1 raised this ("undercuts E6"), and refute-003 doesn't answer it. E6 is still `reasoned`, with "Left for OC1" as its only test and no fallback.
Critique: the user chose a stopgap for its effect, touch players shooting and hopping now. Nothing in the documents says whether that effect is expected on today's devices, or what happens at OC1 if the shared input path is the broken part. The tempting fix is a Risks line that says "OC1 may fail for d0149's reason". That records the gap but doesn't settle what delivery means when it happens.
Consequences: an OC1 failure caused by d0149 would leave a done raft whose Observed criterion is unmet. Someone must decide whether that reopens f0110, blocks `done`, or goes to d0149, and only the user can accept a stopgap that might not work on a phone.
Recommendation: make E6 an experiment with a pass/fail question run before `ready`: on the Beta game on a phone, does dragging the right half look, and does the snap button snap? Those are the same `UserInputService` path, the same `Active = false` frame and the same fold. The lead can ask the user to run it, or record that the user already knows the answer.
- On pass, E6 is `run` and OC1 stands.
- On fail, escalate to the user, saying what each option costs:
  - (a) land anyway, with OC1 deferred to d0149's fix and a `Decided with the user` line;
  - (b) wait for d0149's diagnosis;
  - (c) widen this raft to fix the shared path.
- Either way, add a Risks line that names d0149's report.
Lesson: z-design/accepted-risks-checked-and-decided

Verdict: changes

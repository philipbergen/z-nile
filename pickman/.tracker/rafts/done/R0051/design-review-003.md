# Review 003: R0051 (design mode)
Inputs: prep worktree at 996f445e plus its uncommitted edits (R0051.md, R0051/check.sh, harvest.md, f0110.md, f0110/check.sh, f0110/acceptance/{buttons,fold,adapters,hunt}.spec.luau, game-design.md, architecture.md, the two new lessons); design-review-001/002 and design-refute-001/002; `./zn capture f0110` (f880bedb); origin/main at 2f7a712a; PR #127 (`capture-touch-controls` @ eff4b96a); prototype `proto-f0110` at dc6c8bf1 (its four specs are byte-identical to the sequestered ones, `cmp`); CI run 40236303256.
Dropped from design-review-002: F1, F2 (both answered `fixed`, and both fixes hold: see below).

Rulings on design-refute-002:
- F1 fixed. `expectDrawn` now pins the caption's `Name`, `Font` and `TextXAlignment`. I re-ran M26 on the prototype (`TextXAlignment.Left`): `adapters.spec:406: expected "Center", got "Left"`, `9 passed, 1 failed`. Then I restored the prototype from a copy, and `git status` is clean. The lesson's check now walks the Design's sentence.
- F2 fixed. The placement table (f0110.md lines 48 to 62) has no blank line in it.

Also checked and sound:
- Prototype specs. f0110, f0027/28/29, f0100/01/04, `tests/unit/Touch`, `touch-adapters`, `hud-shots` and `tests/meta/architecture`: 255 passed, 0 failed (35 files).
- Prep tree. `./zn check f0110`: AC1 to AC4 fail and AC5 and AC6 pass, as E3 says.
- Drift. `git diff d8a9a9aa origin/main -- pickman/src pickman/tests` is empty, so the prototype's base is still current for every file the specs load.
- Wiring. Main's `Controls.start` call is pinned positionally enough: f0028 pins its prefix and `Camera.holdMouse`, and f0110 pins that it ends in `HudView.buttons`.
- The touch look never springs back (only the arrows spring, View `step`), so a fire tap after a look drag aims the way the hunt spec assumes.

### F1 [high] The user folded f0110 into the new defect d0149 and is removing f0110's folder, and d0149 replaces the controls this design extends
Where: R0051 (its only member is f0110); f0110 Solution and Design; game-design.md's new Mobile bullet "Fire and hop"; f0110 E6 and OC1.
Evidence:
- Main gained `f447541a tracker: new d0149 touch-circle-controls` (14:36 today). PR #127 (`capture-touch-controls`, open, head eff4b96a, "tracker: new d0149 Touch circle controls (f0110 folded in, the user's decision)") deletes `pickman/.tracker/issues/f0110/{f0110.md,check.sh,spend.md}`. It gives d0149's Problem the line: `Scope decision (user, 2026-10-25): "Fold f0110 into the new defect": f0110 ("Touch fire and hop" …) is folded into this issue and removed.`
- The user's request, quoted there: "the touch controls do not work. Show two circles on screen that users pull on to steer (left circle) and view (right circle), tapping right circle is jump. add circle-buttons for shoot and pick on the right". This prep's design is the opposite on each point:
  - It makes jump a separate JUMP button in Roblox's jump corner. The user asks for a tap on the right (look) circle.
  - It extends the swipe-left/drag-right half zones (`Touch.zone`'s halves and the fold). d0149 says those don't work on a phone and replaces them.
  - It leaves no room for a pick button.
- d0149's Solution makes finding out why today's touch fails (f0027 and f0028 on a real phone) the first step. That undercuts E6 ("A Frame with `Active = false` lets the touch through to `UserInputService` … Left for OC1"). It also undercuts this design's premise, from which AC4 and OC1 follow, that the existing touch path works on a device.
- f0126 (wall picks, `preparing` on main since 3ef58b8f) lists "a touch control for the pick (f0110's area …)" as a non-goal. c0150 (new on main) narrows the f0104 key pins so f0126 can add a pick key in `Controls`, which this raft also changes.
Critique: the prep's only member is being removed by a user decision this design predates. If both PRs land, either the prep PR hits a modify/delete conflict on f0110's folder, or #127 lands after it and removes an item the raft has made `reviewed`. Either way game-design.md would record a **(prep)** Mobile decision (JUMP as its own button, finger-down buttons outside the look zone) that the user has already overruled. The tempting fix is to approve R0051 as a "stepping stone" and let d0149 rework it. That decides the user's scope question for them: the user chose to fold, not to sequence. It also lands a JUMP button, a hop zone and a `Touch -> Hud` edge that d0149 may remove, with promoted specs (f0110's `buttons`, `fold`, `adapters`) that d0149 would then have to override.
Consequences: whichever way it goes, R0051 exists on main (d8a9a9aa), so it must be stopped or retired by the tracker's own command, never by hand. This prep's uncommitted work (the placement probe, the shared `fire()`, the specs, 28 run mutants, the lessons `prep-choices-marked-and-checked` and `drawn-from-the-visible-root`, and `harvest.md`) is lost unless something carries it. The two lessons are general and worth keeping whatever happens to the raft.
Recommendation: escalate to the user. Don't land or ready R0051 until they answer, and give them these options:
- (a) Follow the fold as decided. Stop R0051 and give d0149's prep this prep's findings as input: the placement table, the fire path through Controls.keys' aim, the Rules and mutants, and the specs as a starting point. Land the two lessons and their harvest notes separately (for example a lesson-capture chore). The cost: this prep's design rounds are spent, and fire and hop wait for d0149's redesign.
- (b) Land R0051 first as an interim. The cost: d0149 overrides f0110's promoted specs and game-design.md's bullet, PR #127 must be redone (it deletes a folder this PR changes), and the user's fold decision is reversed for now. Only the user can choose this.
- (c) Any split the user names, for example keeping the FIRE path and dropping JUMP in favour of the right-circle tap. That changes this design and needs a new round.

Under any option, record the answer as a `Scope decision (user, …)` line on whichever item carries fire and hop.
Lesson: z-design/design-the-execution-window

### F2 [low] E5 still describes round 1's specs; the run on round 2's specs isn't recorded
Where: f0110 Unknowns & experiments E5 ("the third run (40235065457, `proto-f0110` @ a95a0c68, the specs byte-identical to the sequestered ones after round 1)").
Evidence: round 2's F1 fix changed `adapters.spec.luau` (three assertions, `git diff a95a0c68 dc6c8bf1`), so a95a0c68's specs are no longer the sequestered ones. Run 40236303256 (headSha dc6c8bf1, today's specs) was in flight when I reviewed: `gate (pickman)` had succeeded and `gate (z-nile)` was still in progress.
Critique: the record says a platform ran the current specs when it ran an earlier version. This is round 1's F4 again, one round later.
Consequences: none.
Recommendation: if R0051 goes on (F1 option b or c), record run 40236303256 with its sha and the final result of both jobs in E5, and make R0051's Experiments phase sentence agree.
Lesson: z-design/prove-specs-pass-on-a-prototype

Verdict: changes

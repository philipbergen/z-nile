# Review 002: c0159 (design mode)
Inputs: prep worktree at 1c6ededd (origin/main a8b51e44 since: tracker-only commits, no change under `pickman/src`, `pickman/tests` or `issues/f0158`) plus the uncommitted c0159 folder (`c0159.md`, `check.sh`, `acceptance/narrowed.spec.luau`, `experiments/narrow.patch`, `experiments/mutants.py`, `design-review-001.md`, `design-refute-001.md`, `harvest.md`) and the `done/f0102` and z-design lesson edits (`git diff`); f0158's `f0158.md` and `acceptance/place.spec.luau`; `./zn capture c0159` and `git show 311cce4c`. Runs in a scratch clone (`git clone --no-hardlinks` of the worktree, `narrow.patch` applied, the c0159 folder and f0102's `check.sh` copied in): `narrowed.spec` 6 passed; `./zn check c0159` 3/3; `mutants.py` BASE pass, N1 N4–N9 killed, N2 N3 ERROR (as E6 records); `./zn promote-check c0159` OK; R0056's DangerHud (`origin/R0056-white-ghost-green-walls`) swapped in: 6 passed. In the worktree (un-narrowed): 2 passed, 4 failed, the ring run listing exactly the Problem's five cases.
Rulings on review 001: F1's insets half is fixed (the spelling pin is gone; the insets-through-a-local variant passes). F1's DisplayOrder half: the refutation is right on scope. The fill (311cce4c) says "its DisplayOrder rules still hold" and "keeping every other pin in the file (… the glows' screen rules …)", so replacing those text pins needs the user. What it leaves open is a coordination gap, which is F1 below. F2 and F3 are fixed and verified (the names-free and dots-in-a-local variants pass every case).
Dropped from design-review-001: F2, F3.

### F1 [medium] f0158's record calls a spelling correct that the DisplayOrder rule c0159 keeps rejects, and the constraint is written only in c0159 (repeat of design-review-001 F1, in part)
Where: c0159.md Design, Existing work ("A Danger screen given an explicit `DisplayOrder = 0`, or an order through a named constant, would fail that pre-existing rule; the capture keeps it, so f0158 must not spell it so"); f0158.md line 183 (Review 004 round); f0158 `acceptance/place.spec.luau` (`danger.DisplayOrder == nil or danger.DisplayOrder == 0`).
Evidence: f0158.md:183: "the two correct adapters the review named (`gui.DisplayOrder = 0` on the Danger screen, the insets through a local) pass". f0158's own place.spec accepts an explicit 0 on the drawn Danger screen. A probe spec (narrowed.spec's helpers, `failing(edited(...))`) in the scratch clone:
```
PROBE Danger screen gets explicit DisplayOrder = 0 (f0158 review 004's correct adapter) => failed: [the danger directions have their own screen, under the radar, the Flow overlay and the HUD]
PROBE ring order through a constant => failed: [the danger directions have their own screen, under the radar, the Flow overlay and the HUD]
```
`grep -n -iE 'DisplayOrder|c0159' pickman/.tracker/issues/f0158/f0158.md` finds no line telling f0158's executor that DangerHud may set only one literal order. Its Design (line 49) says "`DisplayOrder = -1`", and line 53 says "the radar's screen is DisplayOrder 0", which an executor can easily write out explicitly.
Critique: the refute kept the rule as the capture asks, then moved the cost onto f0158 with a sentence in c0159's own document. f0158's executor reads f0158.md, and that document says the opposite. An executor who follows its record gets a red promoted case that a feature can't edit, and stops for another chore. This is exactly zz-review/z-design's "promise for another prep" pattern. The tempting fix is to loosen the kept regex (allow extra `= 0` lines, or identifiers). That changes a pin the capture keeps, which is the user's call.
Consequences: whatever the fix, the two documents must agree before f0158 is rafted. z-raft's Theme quotes the members' decisions, and f0158's `raft:` is empty today, so this is the window to fix it.
Recommendation: put the constraint in f0158's own record in this round. Add a dated line to f0158.md (its adapter paragraph, or a note under the Review 004 line): "c0159 keeps f0102 place.spec's order rule: DangerHud has exactly one literal `DisplayOrder = <integer>` (the Ring screen's, below 0); the Danger screen sets none; no order through a constant. The Review 004 variant `gui.DisplayOrder = 0` fails it." Make the edit in this prep PR beside the f0102 edits, or send it to f0158's owner and quote the reply in Existing work. If the lead holds that the explicit-0 spelling must stay allowed, escalate to the user: (a) keep the rule and note it in f0158 (no cost beyond the note); (b) let c0159 also accept `DisplayOrder = 0` assignments, which changes a pin the capture keeps. Either way, record the two probes above in Rules and mutants as "f0102's kept rule rejects them (known; f0158 told)". Don't add them as must-pass variants.
Lesson: z-design/quote-other-preps-before-promising

### F2 [low] The renamed screen case says "their own screen, under the radar", but it checks neither, and today the only thing that catches those regressions is f0158's spec
Where: narrow.patch, f0102/place.spec.luau "the danger directions have their own screen, under the radar, the Flow overlay and the HUD"; f0102.md AC5 note.
Evidence: same probe spec:
```
PROBE single screen: ring frames on Danger, Danger at -1 (radar now under Flow) => failed: []
PROBE ring drawn on the radar's screen, no order anywhere but HudView => failed: []
```
The first puts the radar under the Flow overlay, and both pass every case of the three specs. This isn't a regression of the narrowing: the original case was just as blind once a `.ScreenInsets = DeviceSafeInsets` line was present. After f0158 lands, f0158's place.spec catches both: it counts `Ring:GetChildren()` and requires Danger's order to be nil or 0.
Critique: a case name that promises more than it checks misleads the next narrowing. Don't fix it with more text needles (see F1).
Consequences: none if it's only reworded.
Recommendation: say in the f0102 header comment (and the AC5 note) that "own screen, under the radar" is pinned only through the order rule, and that the drawn screens are f0158 place.spec's job. Keep the case name as it is (the digest and c0106's naming are already settled), or rename it to "… one screen below 0, under the Flow overlay and the HUD" and update the digest.

### F3 [low] Two records are stale
Where: c0159.md E5, Affected specs.
Evidence: E5 says "`narrowed.spec` 5 passed"; rerun with R0056's DangerHud it is 6 passed (the CORRECT case came after round 1). Affected specs says c0106's spec "runs under `--full`", but `lune run z-nile/affected -- <the four files>` lists `pickman/tests/acceptance/c0106/narrow-adapter.spec.luau` too (as a touched path itself).
Recommendation: update E5's count and the Affected specs sentence.

Lessons pass: `./zn lessons --when design`. quote-other-preps-before-promising is repeated (F1). The harvest's note on z-design/mutation-runner-runs-correct-variants generalizes the round-1 finding (another chore narrowing for a prepared feature could fail it), so it's a lesson, not a restated finding. Repository safety: the spec only sets an in-memory `Source` and restores it (inside the pcall's fall-through); check.sh runs specs and other items' check.sh only. No writes.

Candidate lesson (for the lead): z-design/quote-other-preps-before-promising, a note: "A constraint one prep puts on another ('f0158 must not spell it so') is written into the other prep's document in the same round. A sentence in the constraining prep is read only by its own executor. Check: for every 'X must / must not' about another item, does X's own document say it?"

Verdict: changes

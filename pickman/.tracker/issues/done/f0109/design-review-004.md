# Review 004: f0109 (design mode)
Inputs: prep-white-ghost-green-walls 4cc59ded (f0109.md, check.sh, acceptance/colors.spec.luau, place.spec.luau, docs.spec.luau, design-review-003.md, design-refute-003.md, harvest.md; `git diff dc2405a3 4cc59ded`); prototype `.worktree/proto-f0109` (base ee121ddc, uncommitted diff; its `tests/acceptance/f0109` identical to the item's `acceptance/`). Experiments in a scratch clone at **today's origin/main 9aa889df** (not the prototype's base: c0128 has since narrowed f0024 and f0026, two fake-engine specs, and changed game-design.md) with the prototype's diff applied (`git apply --3way`: all six files clean) and its specs copied.
Dropped from design-review-003: F1, F3

Rulings on refute 003:
- F1 fixed. Both cases now walk (true, false), the real level-clear flash, before the edible part, and the radar list holds all four combinations. Re-run in the scratch clone (`lune run tests/run -- tests/acceptance/f0109/place.spec.luau`), each mutant an exact substitution, the source restored between runs:
  - MM1 (MazeView `View.wallColor(Lit and Edible, Edible)`): `4 passed, 1 failed`.
  - DM1 (DangerHud `if wallEdible then View.wallColor(wallLit, wallEdible) else View.WALL_COLOR`): `4 passed, 1 failed`, on the assertion (`place.spec:186: expected "255,255,255", got "33,33,222"`), not a crash.
  - DM2, mine (the radar flashes only when not edible: `View.wallColor(wallLit and not wallEdible, wallEdible)`): `4 passed, 1 failed` (the (T,T) state).
  - Unmutated, with every fake-engine spec (`grep -rlE fakeengine tests | grep spec.luau`: f0065 ×4, f0025, f0024, f0061, f0109 place, flow-rank-prompt, f0026) plus f0109's three specs and c0128's three: `146 passed, 0 failed, 16 spec files`. So the design still holds on today's main, c0128's narrowed f0024/f0026 included.
- F2 partly fixed: see F1 below.
- F3 fixed: the Regression guard names f0146 and what the second to land owes.

### F1 [low] Stale margin still in the Design, and E1's corrected sentence now contradicts itself (repeat of review-003 F2)
Where: f0109.md:39 (Design, "Inky's colour"): "CIE76 distance ≥ 45 from every other drawn colour … lemon is 31.4 from it"; E1 (f0109.md:73): "gold 31.4 since the brighter gold (255, 215, 0) (31.4 (since the brighter gold) against the first gold, 255, 191, 0) (its nearest)".
Evidence: `grep -n "≥ 45" f0109.md` still hits line 39, which review 003 F2 asked to restate as "≥ 30". E1 now says lemon is 31.4 from *both* golds; review 003 measured 31.4 against (255, 215, 0) and the earlier text measured 45.4 against (255, 191, 0).
Critique: a mechanical edit garbled the sentence; the bar a reader takes away (45) is still wrong. No spec depends on it (colors.spec checks ≥ 30).
Consequences: none.
Recommendation: Design line 39: "CIE76 distance ≥ 30 from every other drawn colour (lemon 31.4 from f0126's gold, its nearest)"; E1: "gold (255, 215, 0) 31.4, its nearest (45.4 from the first gold, 255, 191, 0)".
Lesson: z-design/restated-rules-move-together

### F2 [low] The Regression guard doesn't name f0158, which depends on f0109 and rewrites DangerHud and View
Where: Regression guard. `git worktree list` this round: prep-danger-radar-ring 99eb0d91 (f0158, `depends_on: [f0109, c0159]`), whose prototype (proto-f0158 54de0bc2) changes `pickman/src/client/DangerHud.luau` and `pickman/src/shared/Logic/View/init.luau` (adds `View.DANGER_COLOR`) and states "its wall dots take f0109's `View.wallColor`".
Evidence: f0109's radar case excludes radar children by two literal colours of DangerHud, `YOU = "255,255,0"` and `BLIP = "255,60,60"`. f0158's prototype leaves the radar's blip colours as they are (only the ring, a separate screen, takes `DANGER_COLOR`), so today nothing breaks; but any later change of the radar's blip colour turns f0109's promoted case red with "expected <wall colour>, got <blip colour>".
Critique: f0158 lands second and owns keeping f0109's promoted spec green, so this is a note, not a defect; naming it lets f0158 (and anyone changing the radar's blips) know the literal it must keep.
Consequences: none.
Recommendation: one Regression guard line: "f0158 (danger ring) depends on f0109 and edits DangerHud and View; f0109's radar case excludes the radar's "you" dot (255,255,0) and hunting blip (255,60,60) by colour, so a change to either is an override of f0109's place.spec."

Candidate lesson (for the lead): none new; F1 is a second instance of z-design/restated-rules-move-together (a requested restatement applied to two of three places). Note for the reviewer: run a re-review's evidence against today's origin/main, not only the prototype's base, when main has moved under files the specs load (here c0128's narrowing of two fake-engine specs).

Verdict: approve

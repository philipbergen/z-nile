# Review 002: f0125 (design mode)
Inputs: prep-player-faster 77956ca0 (f0125.md, check.sh, acceptance/speeds.spec.luau, acceptance/docs.spec.luau, design-review-001.md, design-refute-001.md, harvest.md); prototype `.worktree/proto-f0125` (base d24aabc8, uncommitted diff; its `tests/acceptance/f0125` is identical to the item's `acceptance/`); `./zn capture f0125` (1213f851). Experiments in a scratch clone (d24aabc8 + the prototype's diff + its specs), `speeds.spec` run singly.
Dropped from design-review-001: F1, F2, F3, F4, F5

Rulings on refute 001:
- F1 fixed. The motion case measures Blinky's units per step along the rails on levels 1 and 5, hunting, frightened and as eyes. Re-run in the scratch clone: the prototype gives `9 passed`; **MX1** (`baseSpeed = s.config.movement.speed * (s.config.ghostTuning or 1)`) gives `level 1 hunting: a step covered 23 units, want 26`; **MX2** (the eyes speed in `speedOf` times `set.tuning`) gives `level 1 eyes: a step covered 54 units, want 60`. Both are killed.
- F2 fixed. The Design and Maintainability now give `Session.speeds` its real role: the step's source for the player, and the oracle for the ghosts, tied to them by the motion case. M7 is recorded as an equivalent mutant left to code review, and the Regression guard names f0143's step line and f0126's `set.tuning`. f0143's own document (prep-speed-boost-escape 76b6941e, lines 71 and 220) still says `Levels.playerSpeed(...)` and "base 33". The coordinator owns that hand-off, so this is not a finding here.
- F3: the bound is in. **B1** (the bound dropped) gives `8 passed, 1 failed` on the too-fast case, so it is killed. But the case can't tell this bound from a stricter wrong one: see F1 below.
- F4 fixed: 9.3 s against 12.3 s, floor 8 s, recorded.
- F5 fixed: the open question now reads "answered by f0125", and `docs.spec` checks it.

### F1 [high] AC5's "more than a tile a tick" can be passed by refusing every `ghostTuning` above 1
Where: `acceptance/speeds.spec.luau:174-187` ("a ghost tuning that would move a ghost more than one tile a tick is refused …"); AC5; Rules and mutants row "a tuning that makes a ghost faster than a tile a tick is refused" (B1 only).
Evidence: mutant KGT1 in the scratch clone replaces the per-level loop in `Session.new` with `if k ~= nil and k > 1 then error("too fast", 0) end` (the loop disabled). `lune run tests/run -- tests/acceptance/f0125/speeds.spec.luau` gives `9 passed, 0 failed`. The case tests three configs: base 96 with k = 1.1 (refused under both rules), base 96 untuned (k nil, so it skips both rules), and `GAME_CONFIG` (k = 1/1.1 < 1). No case accepts a k above 1 that the real bound allows, and no case sits next to 120. Review 001 F3 named "k ≤ 1" as the product rule nobody asked for, and the spec still can't tell it apart from the real bound.
Critique: AC5 states a speed bound, and a different rule (no faster ghosts at all) passes it. The obvious patch, one more accepted case at a small k, still lets an off-by-one (`>=` against `>`) through.
Consequences: the cases have to sit on both sides of the bound at one base: the largest k whose fastest ghost (level 5, `normal`) rounds to exactly 120 is accepted, and the next one up (121) is refused. The level and kind loop must stay covered: base 96 with k = 1.1 already rejects a level-1-only check (level 1 is 99, level 5 is 125). `normal` always dominates `tunnel` and `frightened` (`speedFactor` is above both in every row of `Levels`), so a mutant that checks `normal` only is equivalent. Record it as such, so nobody adds a case that can't fail.
Recommendation: add to the case:
- `GAME_CONFIG`'s base (30) with k = 2 is accepted (level 5's ghost is 71). This kills KGT1.
- At base 96, a k that gives exactly 120 is accepted (`round(96 × 0.95/0.8 × k) = 120`, for example k = 1.0526) and one that gives 121 is refused. This kills `>=`.

Add KGT1 and the `>=` mutant as `run` rows. Record "normal only" as an equivalent mutant.

### F2 [low] The bound is skipped when `ghostTuning` is nil, so the classic default is protected only by `Levels.GHOST_TUNING` staying 1
Where: prototype `Session.new` (`if k ~= nil then for level = 1, Levels.COUNT …`); Design "Config and validation".
Evidence: the loop runs only for a set `ghostTuning`. `Session.speeds` resolves `c.ghostTuning or Levels.GHOST_TUNING`, and the bound doesn't. If anyone later sets `Levels.GHOST_TUNING` above 1 (the Slower-ghosts row still names it as "the" factor), the bound skips every config that leaves the field nil. That includes `DEFAULT_CONFIG` and every spec's config.
Critique: one rule (one-rule-one-function) is resolved two ways: the speeds read the default and the bound doesn't. Today it's harmless at GHOST_TUNING = 1.
Consequences: with `k = c.ghostTuning or Levels.GHOST_TUNING`, the bound also runs on untuned configs. At k = 1, base 96's fastest ghost is 114, so f0018's pins (96 accepted, 97 refused by `checkLevelSpeeds`) don't change. The validity check (positive finite) still applies only to a set field.
Recommendation: resolve k once, as `Session.speeds` does, and run the bound on it. The F1 cases already cover the untuned base 96 being accepted.

### F3 [low] The harvest files review 001 F3 under zz-arch/parsers-refuse-ambiguity, which is about repeated fields in a format, not a speed bound
Where: `harvest.md` line "design-review-001 F3: zz-arch/parsers-refuse-ambiguity".
Evidence: that lesson's check reads "Can this format hold every repeat of what it records … does its parser refuse a repeated or ambiguous field". F3 was a missing upper bound on a config number, checked against the engine's contact model.
Critique: a wrong mapping adds a source count to a lesson that didn't apply, and the real lesson (a numeric config is bounded by what the consumer can handle) is lost.
Consequences: none.
Recommendation: map it to the lesson the lead writes from F1's candidate below (a refusal's case sits on both sides of the bound), or mark it as a one-off.

Candidate lesson (for the lead): a refusal's spec sits on both sides of its bound. It accepts the largest value the rule allows, refuses the next one, and accepts a value that only a simpler wrong rule would refuse (here k > 1). Check: "for each refusal, which stricter rule also passes my cases?"

Verdict: changes

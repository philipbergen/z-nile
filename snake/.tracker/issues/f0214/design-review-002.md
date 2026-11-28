# Design Review 002 — f0214

Verdict: approve

## Verification of Round 1 Findings

- **F1 [high]** (`acceptance/golden.spec.luau:290-313`, `f0214.md:213`): Verified. `golden.spec.luau` now initializes `w.golden.timer = 1.0` and `w.goldenTimer = 1.0`, steps `0.25 s` into `MAP CLEAR`, and asserts both timers pause at `0.75 ± 1e-6` across `World.advance(w, 1.5, d)` before resetting on map 2. `Unknowns & experiments` (`f0214.md:213`) records the prototype and mutation run.
- **F2 [high]** (`acceptance/boost.spec.luau:102-115,282-309`, `acceptance/golden.spec.luau:315-405`, `f0214.md:244,255`): Verified. `boost.spec.luau` tests non-step-aligned shedding on map 2 (`0.55 s`) and runs frame-rate cuts across maps 1 and 2; `golden.spec.luau` tests non-step-aligned `goldenTimer = 0.3` and `golden.timer = 0.15` before respawn as well as steered eating on map 2 across `{1/60}`, `{1/30}`, and `{0.07, 0.013}` cuts.
- **F3 [high]** (`acceptance/golden.spec.luau:107-137`, `acceptance/crumbs.spec.luau:173,181-209`, `f0214.md:245,261`): Verified. `golden.spec.luau` adds the crowded 5×5 board case leaving only 2 free tiles across 8 seeds, and `crumbs.spec.luau` asserts `#w.apples == #w.snakes + 1` and adds the shared-arena death case where odd pre-step tiles overlap an apple, a golden apple, an existing crumb, and a survivor's new head.
- **F4 [medium]** (`acceptance/boost.spec.luau:94,216-225`, `acceptance/golden.spec.luau:139-170`, `acceptance/crumbs.spec.luau:211-228`, `acceptance/integration.spec.luau:116`, `f0214.md:234,241,247,262`): Verified. Instant-order assertions (shed before step at `t = 0.5 s`, expiry before spawn, expiry before step), `w.halfStep = true` reset on `World.start`, head-on collision on a crumb, `crumbsEaten >= 1`, and the corresponding `Rules and mutants` rows (`B4b`, `B12b`, `G3b`, `G3c`, `C8c`) are all present and accurate.
- **F5 [low]** (`f0214.md:138,142,144,156`): Verified. `World.advance` specifies `> eps` guards in `nextDt`, phase-preserving resets (`math.max(0, timer) + interval`) for `shedTimer` and `goldenTimer`, and unconditional `#s.body >= Maps.goal(w.map)` checking across surviving snakes.

## Findings

None.

---
title: Every tuning a check accepts keeps the outputs finite
when: design
tags: [input, thresholds, nan]
check: For each value a tuning's check accepts at its edge (a dead zone of 0, a rate of 0), does every function using it stay finite on the commonest input (a resting stick, an empty list, a zero length), with a case that runs it?
---
A tuning check states the range a value may take, and the formulas must hold over the whole range, its closed edges included. A guard written as `r < dead` is safe for any dead zone above 0 and divides 0 by 0 at a dead zone of 0, on the input that happens most (a stick at rest).

**Why:** f0203 design review 001 F6: `Pad.tune` accepted `lookDead = 0`, and `Pad.look(0, 0, dt)` then computed `-0 * (0 / 0)`, a NaN look, although the Design promised errors instead of NaNs.

**How to apply:** for each accepted edge value, evaluate each formula at the commonest input, and write the guard so the edge is covered (`r <= dead`); add the case and the `<` mutant to Rules and mutants.

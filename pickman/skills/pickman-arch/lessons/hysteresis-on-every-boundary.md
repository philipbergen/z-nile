---
title: Hysteresis on every boundary an input can sit on
when: design
tags: [input, thresholds]
check: For each boundary a continuous input is mapped across (radius, angle, sector), can a held input sitting on it wobble across and emit an event each frame?
---
A continuous input (a stick, a tilt, a drag) folded into discrete events needs hysteresis on every boundary it can rest on, not only the one the design thought of. A radial dead zone with on and off thresholds still flips between sectors every frame when the thumb rests on a diagonal.

**Why:** f0146 design review 001 F3: `Pad.steer` had radial hysteresis (`STEER_ON` 0.6, `STEER_OFF` 0.4) but none in angle. A ±1° wobble at 135° emitted `Forward, Left` alternately each frame, each `Forward` cancelled the buffered turn, and the rate limit dropped the rest. The user chose a 15° margin past the diagonal.

**How to apply:** list each boundary of the fold (each threshold and each sector edge), give each one a margin, and add a case that wobbles the input on it and expects one event. Add the no-margin mutant to Rules and mutants.

---
title: Hysteresis on every boundary an input can sit on
when: design
tags: [input, thresholds]
check: For each boundary a continuous input is mapped across (radius, angle, sector), can a held input sitting on it wobble across and emit an event each frame? And when the fold's state is read as a held value (a held move or rotate) rather than as a one-shot event, does a case pin what it holds in every region on both sides of the band (released, the held side short of on, the other side short of on, the other side past on)?
---
A continuous input (a stick, a tilt, a drag) folded into discrete events needs hysteresis on every boundary it can rest on, not only the one the design thought of. A radial dead zone with on and off thresholds still flips between sectors every frame when the thumb rests on a diagonal.

**Why:** f0146 design review 001 F3: `Pad.steer` had radial hysteresis (`STEER_ON` 0.6, `STEER_OFF` 0.4) but none in angle. A ±1° wobble at 135° emitted `Forward, Left` alternately each frame, each `Forward` cancelled the buffered turn, and the rate limit dropped the rest. The user chose a 15° margin past the diagonal.

**How to apply:** list each boundary of the fold (each threshold and each sector edge), give each one a margin, and add a case that wobbles the input on it and expects one event. Add the no-margin mutant to Rules and mutants.

A band that is harmless for one-shot sectors can be wrong for a held state. f0203 design review 001 F5: arcade's `"horizontal"` fold kept holding "left" while the stick read +0.5 (past the centre, short of `on`), so a cannon held left while the player pushed right. A fold whose state is held never holds the side the input is not on: there it releases.

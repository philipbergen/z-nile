---
title: Feed a user-decided range from the real producer's extremes
when: design
tags: [specs, ranges, fixtures]
check: When a user-decided output range (an opacity, a size, a speed) depends on an input another function produces, does one case feed that real producer at its extremes (its floor, its cap, its cutoff) and assert both ends of the user's range, rather than only hand-built inputs?
---
A pure function tested only with hand-built inputs never sees the range its real producer hands it. A floor, a cap or a cutoff in the producer narrows the output, so a range the user decided is never drawn in full while every case stays green.

**Why:** f0158 design review 003 F1: the danger ring drew lit dots at `lit.min + (lit.max - lit.min) × brightness`, and the user decided 35–85%. ring.spec built its indicators by hand, but `Awareness.indicators` never gives a brightness below 0.3, so the farthest lit dot was drawn at 50% and nothing failed.

**How to apply:** for each user-decided range, find the input the output is computed from and its real producer. Add one case that runs the producer at both of its extremes (here, a ghost on the player's tile and one at the farthest indicated distance) and asserts the user's two ends. If the producer's range doesn't reach them, map from the quantity it does span (here, distance), and say so in the Design.

---
title: On the wrapping field, a distance rule needs a case where the short way and the raw difference disagree
when: both
tags: [wrap, geometry, cases]
check: For each Field.distance or Field.delta a rule reads, does some case put its points so that a raw subtraction picks a different answer (either side of an edge), and not only in symmetric placements where the two agree?
---
Asteroids' field wraps, so every rule that reads a distance or a direction must read it the short way across the wrap (`Field.distance`, `Field.delta`). A case whose points sit away from the edges, or symmetric about the field (two homes exactly half the field apart), gives the same answer the short way and by a raw subtraction, so it passes a rule that forgot the wrap.

**Why:** f0221 design review 001 F1: the saucer's choice of the nearer ship passed with a raw distance, because every case used the two homes, 512 apart; saucers enter and leave at the left and right edges, where the wrap decides the target. The bounce had its wrap case (across the right edge); the saucer's target, which reads the same kind of distance, didn't.

**How to apply:** for each rule that reads a distance or a direction (a target, a clear radius, a collision, a spawn point), add a case with the points either side of an edge where the raw subtraction names the other answer, and its mirror; give the row the mutant "the raw difference".

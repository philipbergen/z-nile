---
title: A printed "it counts for X" is checked against what X reads
when: design
tags: [texts, promises, specs]
check: For every line the design prints that promises a later command will accept the result ("it counts for ./zn done", "ready will take it"), which state does that command require, and does a case reach that command or that state?
---
A message that tells the person what a later command will do is a claim about that command's code, not about the one printing it. If nothing checks the claim, the person follows it and the later command refuses.

**Why:** c0369 design review 003 F2: approve, run on a raft's layer branch, printed that the record "counts for ./zn finish and ./zn done", but `done` lands only the published top-layer tip of finished layers, and an `approval.md` commit above a finish leaves the layer unfinished; the spec checked only `approve --check`, which is what `finish` reads.

**How to apply:** for each such line, read the later command's refusals, write the state it needs into the line (or make the command reach it), and add a case that runs the later command, or checks the state it reads.

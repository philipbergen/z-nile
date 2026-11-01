---
title: Every review round's fixes rerun the whole regression sweep
when: design
tags: [specs, regression, review]
check: Since this round's fixes, has the whole prototype suite been rerun, together with every dependency's and every in-flight prep's sequestered specs that load a changed adapter or quote changed document text, and do the Unknowns' numbers come from that run, not from an earlier round?
---
A fix answers one finding and changes code or text other specs read. The sweep the design recorded in round one says nothing about the tree after round two.

**Why:** d0149 design review 002 F2, F3: round one's fixes added a `RunService.Heartbeat` connection to Controls (turning all five of f0126's Controls cases red, its stub having no RunService) and rewrote game-design.md's boost sentence (turning f0143's place.spec red), while E4 still quoted round one's 1420/74.

**How to apply:** after answering a round, rerun the full suite on the prototype and every dependency's and in-flight prep's specs that read what changed (grep their acceptance folders for the module or phrase), and replace the recorded numbers.

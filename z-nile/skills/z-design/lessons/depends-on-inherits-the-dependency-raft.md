---
title: A new depends_on waits for everything the dependency's raft waits for
when: design
tags: [coordination, dependencies, rafts]
check: When this design adds a depends_on on an issue that sits in a readied raft, what does that raft wait for (its Order), and does its executor's prompt edit my document and so turn the grouped hash of a raft holding it stale?
---
A dependency is on the whole chain behind it, and a step in the other raft's prompt that edits this issue's document invalidates an earlier raft grouping.

**Why:** c0189 re-prep, design review 007 F1, F2: depends_on: [c0194] meant waiting for R0078 and R0070 too, with c0123 behind; c0194's step 8 adds a note under c0189.md, so c0189 may only be rafted after R0070 is done. The order itself was the user's (G5).

**How to apply:** read the dependency raft's Order and Implementation steps before adding the edge; name the chain and the rafting rule in Risks; put the order to the user as a guess.

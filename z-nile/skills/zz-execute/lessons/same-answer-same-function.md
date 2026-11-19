---
title: When the design says two paths use one answer, the build calls one function
when: both
tags: [drift, helpers, layers]
check: For each value the design says two code paths share (the same layer, the same place, the same rule), does the build call the one function that already computes it, rather than a private copy of its logic?
---
A new helper that re-derives what an existing function answers agrees with it on the day it is written and drifts the first time either copy is fixed. zz-test/one-rule-one-function states the rule for specs and scripts; this is the build's side of it.

**Why:** R0130 final review 001 F2 (c0369, 2026-11-18): the design says the raft worktree is judged by the same top layer the acting run records on and pushes (`layergit.layersOf`), but `approveplace.luau` carried its own `topLayer` loop over the same refs. They agreed, but the split is the shape of c0369 design review 004 F1, where a retry pushed a different layer from the one that was judged. The fix calls `layergit.layersOf` and keeps only the choice between the local ref and origin's.

**How to apply:** when a design sentence says "the same X as Y", grep for the function that computes X for Y and call it; write a private helper only for what that function does not answer, and say so in a comment.

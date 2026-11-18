---
title: A test seam feeds a guard's inputs and never adds a branch to the guarded path
when: design
tags: [specs, seams, guards]
check: With the seam unset, does the code under test run an expression that no check executes, because every spec sets the seam?
from: c0225 design review 001 F3 (c0225 withdrawn 2026-11-16)
---
A seam that only reassigns an input leaves the real path as it was. A seam that makes the guarded line branch on whether it is set adds an arm only an unseamed run takes, and no spec can run an unseamed arm of a guard that would stop its own workers. A wrong implementation of that arm then passes every check, and when the guard fails nothing turns red.

**Why:** c0225 design review 001 F3: the first patch filtered the scan line by `%from` (`%from ? grep {...} @cand : @cand`); a "simplified" `exists $from{$_} && ...` would have stopped nothing in a real sweep and passed all eight checks.

**How to apply:** let the seam feed the same variable the real path reads (here `@cand`, with later entries parked in `%later` and moved in at each scan), keep the guarded line unchanged, and add a check.sh-only real run for the unseamed path.

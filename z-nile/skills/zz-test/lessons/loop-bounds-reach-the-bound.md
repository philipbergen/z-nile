---
title: A loop bound needs a case that reaches it and one that would go past it
when: design
tags: [loops, bounds, mutants]
check: For each limit the design states ("at most N tries"), does some case drive the loop to N, and past it, and does a case pin what happens right at the limit?
---
Cases that stop early pass with any bound, or none: a cap of two, a cap of four and an unbounded loop all look the same when every case ends after the first or second pass.

**Why:** c0152 design review 004 F1: merge-check's "at most three trials" had no case beyond two trials, because the test moved main only once per check; a cap of two or no cap passed every spec, and what happens after the third trial (a spend-only move is ok, any other is a no) was neither stated nor tested.

**How to apply:** make the test's driver able to repeat (here a queue of commits the probe pushes, one per trial), with more steps prepared than the bound so an unbounded mutant still stops; add a case that hits the bound and one for each outcome at it; list cap N-1, cap N+1 and no cap as mutants.

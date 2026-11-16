---
title: When a change splits a loop's iterations into kinds, every limit says which kinds it counts
when: design
tags: [loops, limits, mutants]
check: What did the old loop's bound become after the split, and is the mutant that counts the other kinds listed in Rules and mutants with a case that fails it?
---
A change that adds a kind of iteration (here empty scans next to stopping ones) leaves the old bound counting "every iteration" unless the design says otherwise. The minimal edit keeps the old counter and the new kind spends it, so a clean run hits the limit.

**Why:** c0225 design review 001 F5: the table listed only "the 50-limit dropped"; keeping `for 1 .. 50` with empty scans spending passes passed every check and would end a clean run with 71 after ten stopping scans.

**How to apply:** write the bound as "only <kind> counts", add the row with the mutant "the limit counts every iteration", and pin it with a case (a check.sh-only one when it is slow).

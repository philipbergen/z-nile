---
title: A rule that skips part of a step proves the rest is unchanged
when: both
tags: [specs, mutants, coverage]
check: When a rule skips part of a step (contacts, eating, a timer) under some condition, is there a spec that runs the same fixture with and without the condition and asserts everything the rule does not skip comes out identical?
---
"Skip X while Y" is easy to implement as "skip the whole block that contains X", which also stops everything else in that block. Specs that only check X is skipped stay green, because the over-skip makes X's absence even more certain.

**Why:** R0035 design review 005 F3: skipping `stepGhosts` while the player was airborne froze every ghost, their house release and their frightened time, and passed every acceptance spec, because frozen ghosts can't catch anyone either.

**How to apply:** for each skip, write a twin-run case: the same seed and fixture, once with the condition and once without, chosen so the condition changes nothing else, and assert the unskipped state (positions, timers, counters) matches step by step and actually changes during the window (so the case is not vacuous). Add the over-skip as a listed mutant.

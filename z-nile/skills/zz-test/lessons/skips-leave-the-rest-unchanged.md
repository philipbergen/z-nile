---
title: A rule that skips part of a step proves the rest is unchanged
when: both
tags: [specs, mutants, coverage]
check: When a rule skips part of a step (contacts, eating, a timer, the player's own move while they stand still) under some condition, is there a spec that runs the same fixture with and without the condition and asserts everything the rule does not skip comes out identical, or, where the condition itself moves the player, that the other agents still move and still meet the player in the window?
---
"Skip X while Y" is easy to implement as "skip the whole block that contains X", which also stops everything else in that block. Specs that only check X is skipped stay green, because the over-skip makes X's absence even more certain.

**Why:** R0035 design review 005 F3: skipping `stepGhosts` while the player was airborne froze every ghost, their house release and their frightened time, and passed every acceptance spec, because frozen ghosts can't catch anyone either.

**How to apply:** for each skip, write a twin-run case: the same seed and fixture, once with the condition and once without, chosen so the condition changes nothing else, and assert the unskipped state (positions, timers, counters) matches step by step and actually changes during the window (so the case is not vacuous). Add the over-skip as a listed mutant.

When the condition is the player standing still (f0126's wall pick), a twin run cannot hold the rest equal: the player's own position differs, and the ghosts chase it. Then assert, for every step of the window, that the other agents' state changes, and find a run where a contact happens inside the window (f0126 design review 001 F1: ghosts frozen during a pick, or no contact during a pick, passed every case).

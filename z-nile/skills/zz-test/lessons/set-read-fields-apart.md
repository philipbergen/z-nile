---
title: Set the field a rule reads apart from its look-alikes
when: both
tags: [fixtures, mutants]
check: For each rule that reads one field (a run's start level, a pick's start tick, a member's own copy), does some case give that field a value different from every field the code could read by mistake (the current level, the current tick, the shared copy), so the wrong read fails?
---
A case that sets two fields to the same value cannot tell which one the code reads.

**Why:** f0147 design review 002 F2: the extra life is `extraLifeScore × start`, and the only case set `start = level = 2`; a mutant reading `level` instead of `start` stayed green.

**How to apply:** for each such rule, add a sub-case where the field differs from each look-alike (start 1 on level 3, start 2 on level 5), and record the mutant that reads the look-alike in the Rules and mutants table.

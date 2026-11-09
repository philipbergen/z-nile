---
title: Read back every prototype edit before explaining a survivor
when: design
tags: [mutation, prototype, experiments]
check: Does each mutation edit refuse a pattern that occurs more than once, and was a surviving mutant read back in the fixture's copy of the code (the pattern it changed, the lines around it) before its survival was explained?
---
A first-match replace changed the wrong branch of a file (`runner.luau` line 141, the start-time check, instead of the run loop's marker branch at line 237); the mutant survived, and the survival was written up as "another path in the engine" until the next review read the fixture's copy.

**Why:** c0279 design review 003 F1.

**How to apply:** make the mutation helper assert that the pattern occurs exactly once (or give the line), print the changed hunk, and look at the fixture's copy of the changed file before writing a word about why a mutant survived.

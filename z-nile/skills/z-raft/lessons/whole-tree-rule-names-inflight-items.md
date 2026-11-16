---
title: A raft that adds a whole-tree gate rule names every in-flight item it will gate
when: design
tags: [raft, gate, lint, in-flight]
from: R0072 design review 001 F2
check: Does the raft's list of work the new rule meets come from the Touched modules of every non-done item, not only from open branches, and does it say which side lists the exceptions?
---
Preps and unrafted issues have no branch yet, so a list built from `git diff` of pushed branches misses them.

**Why:** R0072 design review 001 F2: c0193's lint table covered the open branches; c0180, c0181, c0136 and others have covered Luau files in their Touched modules and meet the lint at their merge.

**How to apply:** search the Touched modules of every non-done issue for the rule's file scope, paste the search, and state "whichever lands second adapts".

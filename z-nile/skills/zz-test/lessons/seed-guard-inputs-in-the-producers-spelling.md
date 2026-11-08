---
title: A spec that seeds a guard's input spells it the way the guard's producer writes it, and appends to the inherited value
when: both
tags: [guards, fixtures, fence]
check: Does the guard canonicalize this side of the comparison or the other (the list's entries), and does the case keep the runner's own entries when it sets the variable?
---
A guard that resolves one side physically and compares it with raw list entries answers "unguarded" for any other spelling; replacing the inherited list drops the real repository from the child's fence.

**Why:** f0265 design review 005 F1: `<git dir>/.` in `PICKMAN_FENCE_REAL_GIT` read as unguarded, and the case replaced the runner's value.

**How to apply:** build the value the way the producer does (`rev-parse --path-format=absolute --git-common-dir`), append it to the inherited value, and assert on an effect that does not depend on the push being allowed.

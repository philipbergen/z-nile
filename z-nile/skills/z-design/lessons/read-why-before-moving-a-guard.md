---
title: Read why a guard sits where it does before you move it
when: design
tags: [guards, history, moves]
check: For the guard, folder or rule this design moves, which review or issue put it where it is, what hole did it close, and does an experiment show the new place closes the same hole?
---
A guard's place is often the answer to an earlier finding. Moving it because "nothing says it must be there" reopens that finding.

**Why:** c0194 asked to move the spec runner's temp folder from the system temp folder into `.cache/.tmp`. A comment said "a spec's `mktemp -d` must land outside .cache" (review 004 F2). The reason was in R0210's history (`git log -S`, `review-004.md`, `refute-004.md`): nothing outside the jail may run from a folder a spec can write, and a promoted spec used `mktemp -d` as its "outside" folder. The move was possible, but only with the jail closing the rest of `.tmp`, the fixture helper refusing temporary trees, and a probe for outer sandboxes.

**How to apply:** `git log -S'<the comment's words>'`, read the review file it cites, write the hole and the spec that relied on it into the Design, and show by experiment that the new place keeps both.

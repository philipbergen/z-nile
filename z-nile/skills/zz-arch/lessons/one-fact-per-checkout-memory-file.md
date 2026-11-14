---
title: A per-checkout memory file means one fact
when: design
tags: [claims, memory, files]
check: Does every reader of this file want the same fact, and does every writer write that fact (not another one the file name also fits)?
---
Reusing a file for a second fact changes what its existing readers decide.

**Why:** c0265 design review 004 F2: `.cache/tracker-claim-<id>` means "this checkout owns the rafting claim" for `release` and `fold` (c0116); reusing it for "the stamp this checkout claimed" turned c0116/claims red. A file of its own kept both rules.

**How to apply:** grep for every reader of the file before writing to it, and make a new fact a new file.

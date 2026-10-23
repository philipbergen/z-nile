---
title: Exhaustive lists name the new thing
when: both
tags: [docs, commands]
check: When this adds a command, file kind or rule, does every exhaustive list in the skills and code (commands allowed in the main checkout, read-only sets, usage text) name it?
---
Some lists claim to be complete: the commands that may run in the main checkout, `READ_ONLY`, the usage text, the command table. A new command missing from one of them is forbidden by the docs or untested by the code.

**Why:** R0040 design review 1 (F8): `lessons` was said to run in the main checkout, but the tracker skill's complete list of main-checkout commands did not name it.

**How to apply:** grep the skills and `z-nile/engine/main.luau` for the lists a sibling command appears in, and add the new one to each, or say why not.

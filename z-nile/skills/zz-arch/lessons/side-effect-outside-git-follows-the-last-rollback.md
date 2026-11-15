---
title: A side effect outside git comes after the last step that can roll back
when: both
tags: [commands, rollback, state]
check: In a multi-step command, is every write outside git (a .cache memory, a marker, a pid file) placed after the last step that can roll the command back?
---
A command that drops local memory and then pushes can roll back the push and leave a claim with no memory, refused by every later command that needs it.

**Why:** R0100 review-002 F1 (`cmd.done` dropped the claim memory before the PR retarget and the push to main, which can call `rollback()`).

**How to apply:** move the drop after the push succeeds and add a spec case with a git shim that rejects the push once.

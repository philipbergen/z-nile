---
title: A change to a file every checkout's engine rewrites says what older engines write there until each has merged it
when: design
tags: [transition, worktrees, shared-files]
check: Does the design change what a command writes into a shared file (the board page, the registry, a counter) that runs from each checkout's own engine, and does it say what an engine from before the change writes there, who sees it, and what restores the new state?
---
`./zn` runs the engine of the checkout it is invoked in. A rebuild of the main checkout's board by a publish from a worktree cut earlier uses the old engine, so the file flips back to the old behaviour until that worktree merges main.

**Why:** c0276 design review 004 F3: after the board marks land, every publish from one of about 70 older worktrees rebuilds the main checkout's board without marks; neither c0276 nor c0265 mentioned it.

**How to apply:** count the worktrees that predate the change, state the transition in Existing work, Usability and the command's documentation, and name the restoring command; put any engine-wide remedy and its cost to the user.

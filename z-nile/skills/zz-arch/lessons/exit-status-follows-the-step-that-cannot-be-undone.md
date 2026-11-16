---
title: A command's exit status follows the step that cannot be undone
when: design
tags: [exit-codes, publish, callers]
check: After which step can this command's effect no longer be undone (a push to origin, a merge), and does every failure after it (a local fast-forward, a board refresh) still report that the effect happened, as success with a warning or a distinct code its callers read?
---
Once a publish has reached origin, a later local failure does not undo it. A command that exits 1 there tells its caller the opposite of what happened, and a caller that acts on the exit status (an app's notice, a retry loop) then misleads the person or repeats the change.

**Why:** c0249 design review 001 F13. `./zn rank` pushed the new rank, then `git pull --ff-only` in the main checkout failed on another command's `index.lock` and `rank` exited 1. The Omarchy app showed "priority not saved" and kept the dragged order, though the rank was on origin/main.

**How to apply:** order the command's steps and mark the one that cannot be undone. After it, a failure exits 0 with a warning on stderr, or with a distinct code the callers handle as "done, not pulled". Add a case that fails the step after it (a lock file in the fixture's `.git`) and asserts the exit status and the caller's reading.

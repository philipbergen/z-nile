---
title: An atomic install never deletes a target another process may have completed
when: both
tags: [concurrency, cache, install]
check: When an install renames into place and the rename fails, does the code check for the completion marker instead of removing the target, and is there a case with two processes on a cold cache?
from: f0427 review F1 (2026-11-21)
---
Two processes installing to one target both lose if the loser removes what the winner just finished.

**Why:** f0427 review F1 (2026-11-21): two `zn` processes on a cold cache, and the finished folder vanished 20 of 20 times.

**How to apply:** build in a private temporary folder, rename into place, and on failure look for the completion marker: if it is there, discard your own copy and use the target. Add a case that starts two installs together and asserts the target survives.

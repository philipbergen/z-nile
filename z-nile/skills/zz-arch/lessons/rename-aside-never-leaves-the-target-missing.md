---
title: A replace by rename never leaves the target missing
when: code
tags: [atomic, rename, cache, concurrency]
check: When code replaces a file or folder that other processes read, is the new one moved into place in one rename, with no moment in which the target name does not exist?
---
Moving the old thing aside and then moving the new one in leaves a window with no target. A second process in that window sees 'missing' and starts its own repair or fails.

**Why:** f0427 step 2 (2026-11-21): the code review found that refreshing the cache by moving the old folder aside first leaves a gap in which a second zn finds no cache. The fix builds beside the target and renames over it.

**How to apply:** build in a sibling temp name, rename onto the target, and only then remove the old copy. Test with two starters at once.

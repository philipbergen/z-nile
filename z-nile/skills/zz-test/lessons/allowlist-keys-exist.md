---
title: An allow-list keyed by path checks that every key names a file
when: both
tags: [guards, stale-text, moves]
check: After a move or a promotion, does every key of this allow-list still name a file the scan visits (or a known future place of one)?
---
A key that names no file allows nothing and fails silently: the scan never visits it, and the file it was meant for, at its new path, is scanned without its allowances.

**Why:** c0120 code review 004 F2. repo-fence's key for c0120's promoted `homes.spec` kept its pre-move path (`tests/acceptance/c0120/…`); the scan now records root-relative paths, so `./zn done c0120` would have turned the gate red with eight names, and `runner-home.spec` had no entry at all.

**How to apply:** add a case that every key is a tracked file, or an unfinished item's spec at the place `done` will promote it to; and simulate the promotion (copy the specs there) and run the scan before the item is done.

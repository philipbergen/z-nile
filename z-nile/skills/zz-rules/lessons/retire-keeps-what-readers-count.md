---
title: Retiring an item keeps the files other readers count
when: design
tags: [retirement, history, data-loss]
check: What reads this item's folder besides its document (lessons, metrics, audit, the board, compaction), and what does each see after the retirement?
---
An item folder holds more than its document: design reviews, refutes, `harvest.md`, spend. Deleting the folder to retire the item removes lesson sources and review rounds that other tools count, so a check that was green (`lessons --check`) turns red and history (metrics) silently shrinks.

**Why:** c0116 design review 001 F2: `recombine` retired an emptied raft with `git rm -r`. Doing what `audit` advised for R0040, today's one orphan, broke `lessons --check` (a lesson lost its only source) and dropped five design rounds from metrics.

**How to apply:** for a retirement, list every reader of the folder and keep the folder where they read it, in a state the item finders skip (c0116: `<root>/rafts/retired/<R-id>` with `retired: <keeper>`). Prove it on a copy of the real tree: the retirement leaves `lessons --check` green and the counts unchanged.

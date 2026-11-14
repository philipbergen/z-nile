---
title: Rows of an append-only record are events only if its writer refuses duplicates
when: design
tags: [records, counting, approval]
check: Can this record get two identical rows, and what does my count say then? Does a row mean the thing I am counting in every case that writes one?
---
Before a design counts rows of a record as events, it reads the writer: what appends a row, whether an identical row is refused, and whether every cause of a row is the event being counted. It also checks when the row is written against when the gate that reads it runs.

**Why:** c0316 design review 001 F1 (2026-11-13): the design read every `approval.md` row from the second as "a redesign after approval". `./zn approve` appends a row every time it runs: 10 of the 13 items with two rows repeated the same hash. A rebase before the build (which the user had ruled is upkeep) also adds a row, and a prep's own new row is written after `status prepared`, so the gate placed there never saw it.

**How to apply:** count changes of the recorded value (a different hash), not rows; say which causes of a change are not the event and how the entry tells them apart; and place the gate after the write.

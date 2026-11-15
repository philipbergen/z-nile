---
title: Text carried from a retired raft's document is checked again in the keeper
when: design
tags: [raft, recombine, stale]
check: After a recombine or fold, has every sentence carried from the other raft's document (its risks, rollback, waits, "lands with its layer" claims, counts of who edits what) been checked against the tree and the new membership?
---
A recombine moves members, not truth. Sentences written for the retired raft assumed its own landing order and its own date; in the keeper some are false, and a prep that landed since has already done what the text says a layer will do.

**Why:** R0094 design review 002 F5 (f0148's game-design section and architecture row had already landed with its prep; "four members edit Session" was three; "no two members change the same function" was false) and R0097 design review 001 F7 (a stale-hook risk, a PR sentence and a rollback line copied from c0123's former raft, false once c0123 lands with c0189).

**How to apply:** for each carried sentence, find the file, commit or member it speaks of and confirm it, or drop it. Count shared modules from the members' Touched lists, not from the old text.

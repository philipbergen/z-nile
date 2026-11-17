---
title: A derived tracked file conflicts across a restack
when: design
tags: [restack, derived-files, spend, stacks]
check: Does any commit this change adds (a review after finish, a landing's bind) rewrite a derived tracked file (a raft's `spend.md`, a summary, a board) that a commit on the other side of a restack also rewrites, and does the design say how restack resolves that file (regenerate it, or take main's copy) while every other conflict still stops?
---
A derived file is rewritten whole by whichever command last records into it. Two such commits on both sides of a rebase conflict on every restack, and a person resolving it by hand can only guess at numbers the tool would have computed.

**Why:** c0248's prototype, after #318 made `finish` write a spend row: a layer's review commit and the landing's bind both rewrote the raft's `spend.md`, and every restack above a landing stopped on it (`./zn check c0248` went from 15/15 to 5/15).

**How to apply:** list the derived files each new commit type writes; for each one a restack can meet, resolve it in the tool by regenerating it or taking main's copy, pin that with a case that restacks over it, and pin with another case that a conflict in any other path still stops.

**Also:** R0110 (2026-11-16): a review fix on layer 1, re-finished, made `./zn restack` stop on the raft's `spend.md`, which layer 1's finish and layer 2's finish both rewrite (two members of one raft, no landing involved). The tool still has no rule for it; the executor rebased by hand, took the layer's copy and let the next `./zn commit` regenerate it.

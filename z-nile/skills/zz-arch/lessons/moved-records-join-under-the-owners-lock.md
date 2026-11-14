---
title: A record moved into another item's run folder joins that item's state under its lock, and never replaces it
when: both
tags: [dispatch, state, lock, adoption]
check: What is already at the destination of this move, and who else writes it while you do? Does the design take the destination's own lock, refuse a live owner with nothing moved, and merge into the state that is there instead of saving its own over it?
---
A design that moves a record (an exchange, a seal, a run) into another item's folder tends to check only the thing it moves, and to save its own state at the destination.

**Why:** c0256, R0093 code review 001 F1: `retry new` adopted the issue a capture had made by saving the capture slot's whole state as the issue's `state.json`, checking only that the issue had no exchange yet. The user had already gone on with `./zn dispatch <id>`, as the stop message told them to, so the issue's own history, step and pending rows were replaced, and a live run of the issue failed on a file it had not written. Six design review rounds had not asked what was at the destination.

**How to apply:** for every move into a folder another run can own, take that folder's lock first and refuse a live holder before anything moves; load the state that is there and add only what the move brings; add a case with a destination that already has a run of its own, and one with a live holder.

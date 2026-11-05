---
title: An action on an item acts on the run that item's state points to, and never creates state for an idle one
when: both
tags: [actions, state, dispatcher, ui]
check: When a run can move from one id to another (an issue's chain following its raft), does the action read the source's own state first (its own run still live means act on it), follow the pointer only when the source's own run is not live and the target has state, and refuse, with a status, an id that has no state instead of calling a command that creates state for it?
---
A UI action keyed by the id on the card reaches the wrong run when the run has moved: c0117's chain on an issue moves to its raft and leaves `follows = <R-id>` behind, so "stop <issue>" answers "not running" while the raft's step keeps going. And a command that writes state as a side effect (`dispatch stop` writes a stop marker and saves) creates state for an id that never ran, which every reader then sees.

**Why:** c0121 design review 003 F3: the board server's Stop ran `./zn dispatch stop <card id>`: on a member card it stopped nothing, and on a card with no run it created `.cache/dispatch/<id>/`.

**How to apply:** read the pointer through the one reader of the state (here c0118's board model, extended with `follows`), act on the pointed-to id when it has state, else the card's own, and answer a clear refusal (409, "nothing is running for <id>") when there is no state; pin both with cases and mutants.

c0121 design review 004 F1: the first fix followed the pointer whenever its target had state, but c0117 writes `follows` once and never clears it, so a step the issue later ran on its own was sent to the raft (and a live raft run would have been stopped). A pointer written once is current only while the source's own state says its run moved: check the source's own outcome before following, and seed fixtures from the writer's real state shape.

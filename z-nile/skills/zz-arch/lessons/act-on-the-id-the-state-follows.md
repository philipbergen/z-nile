---
title: An action on an item acts on the run that item's state points to, and never creates state for an idle one
when: both
tags: [actions, state, dispatcher, ui]
check: When a run can move from one id to another (an issue's chain following its raft), does the action resolve the id from the state (one hop, with a fallback for a stale pointer), and does it refuse, with a status, an id that has no state instead of calling a command that creates state for it?
---
A UI action keyed by the id on the card reaches the wrong run when the run has moved: c0117's chain on an issue moves to its raft and leaves `follows = <R-id>` behind, so "stop <issue>" answers "not running" while the raft's step keeps going. And a command that writes state as a side effect (`dispatch stop` writes a stop marker and saves) creates state for an id that never ran, which every reader then sees.

**Why:** c0121 design review 003 F3: the board server's Stop ran `./zn dispatch stop <card id>`: on a member card it stopped nothing, and on a card with no run it created `.cache/dispatch/<id>/`.

**How to apply:** read the pointer through the one reader of the state (here c0118's board model, extended with `follows`), act on the pointed-to id when it has state, else the card's own, and answer a clear refusal (409, "nothing is running for <id>") when there is no state; pin both with cases and mutants.

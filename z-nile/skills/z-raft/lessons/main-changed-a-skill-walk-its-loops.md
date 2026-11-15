---
title: When main changed a workflow after the members were prepared, walk its loops through the members' refusals
when: design
tags: [raft, main, workflow, refusal]
from: R0100 design review 001 F1, F2, F5
check: For each loop in the skill or command main changed since the members were prepared (stop then ready again, resume by name, take the next one), which refusal of a member does the loop meet next, and which command routes it?
---
A member's refusal is designed against the loops its author knew. A workflow added to main later (z-work) makes a rare path routine and adds callers that never read the member's skill text.

**Why:** R0100 design review 001 F1: z-work turned "stop, ready again, `cd "$(./zn worktree <R>)"`" into the routine block path, where the old worktree still remembers the old stamp and c0274's "no in-place re-adoption" refuses `--adopt` and `done`; the dispatcher's engine-chosen worktree fails the same way, so no skill sentence can fix it. F2 (a discarded session that carries a raft id is sent back into the taker's copy) and F5 (`work` is not in the engine's read-only table) were the same blind spot.

**How to apply:** list the loops of everything main changed (its skill's numbered steps, its engine commands), run each through the members' refusals on the prototype stack, and write what the loop does after each refusal. A fix that needs a member's lookup or refusal to change is the member's re-prep, not a raft sentence.

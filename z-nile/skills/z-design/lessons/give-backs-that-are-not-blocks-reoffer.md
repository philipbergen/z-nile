---
title: A give-back that is not a block puts the item back on offer
when: design
tags: [claims, blocked, loops]
check: When the design lets go of an item without marking it blocked (a stop, a release, a skip list), what does the next `next` print, on this worker and on every other worker, and does the item come back for ever?
---
Releasing a claim (`./zn stop`) makes the item claimable again. A worker that releases a raft it cannot move will be offered it again, by itself or by the next worker, and a skip list kept only in memory idles the worker while others wait.

**Why:** c0253 design review 001 F4. The supervisor gave back a raft that made no progress with `./zn stop`, so it stayed claimable; the skip list idled the supervisor for the rest of the run, and across runs the same raft was claimed and stopped for ever. The user's own words were "marks the raft blocked".

**How to apply:** let go only by the state the user named (blocked, with its escalation note), check the block's exit status before counting it, and add a case where the next pick after the block is another item.

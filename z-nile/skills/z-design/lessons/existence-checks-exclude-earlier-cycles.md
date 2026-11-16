---
title: A check that a step happened ignores what an earlier cycle of the same item left
when: design
tags: [process, refusals, re-prep, records]
check: Can what an earlier cycle of this item left (an earlier prep that landed, an earlier scope's rounds still in this worktree, a round from before the design changed) satisfy this existence check, what in the artifact says which design it was made for, and who writes that record (is it someone other than the party whose change the check exists to catch)?
---
A check that asks only whether an artifact exists (a review round, an approval, a stamp) is satisfied by whatever an earlier cycle of the same item left behind. The proxy "not on origin/main" tells apart only the cycle that already landed; a scope reset in place keeps the earlier scope's rounds untracked in the same worktree, and a fix design that is approved and then rewritten into a closure leaves no boundary at all.

**Why:** c0161's design reviews 001 and 002 (F1 in each). The move to prepared accepted the newest design round in the folder, so a closure decided in a re-prep passed on the old approval (the captured Problem). Comparing with origin/main fixed the landed case and was wrong for c0181's scope reset in place. What held was a record of the design the round read, quoted in the round and compared with the design as it is.

**How to apply:** for each existence check, list the earlier cycles the skills describe (a reclaim, a scope reset, a fix turned into a closure) and ask what tells this cycle's artifact apart. Prefer an artifact that names what it was made for (a hash of the design it read) over a proxy for "new" (a number, a tracked state), have it written by someone other than the party whose change the check exists to catch (a record the author writes proves only what the author saw), and give every rewrite of ids (compact, remap, renumber) a re-record step.

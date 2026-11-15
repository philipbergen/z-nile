---
title: When one function that judges a state is widened, every other judge of that state is asked
when: both
tags: [allow-list, finish, trace, consistency]
check: Which other functions decide the same state (finished, stale, stacked) for the same commits, do they still agree after this change for every layer position, and where they do not, is the disagreement named with its message and recovery?
---
Several functions can answer the same question about the same commits with different rules. Widening one moves what its callers do next while the others still refuse, so a state that could not be reached before now is.

**Why:** d0333 design review 001 F4: `layergit.layerFinishSha` (read by `start`, `stack`, `work next` and `done`'s layer check) and `trace.staleReason` both judge commits after a finish commit. The fix let both take the raft's `spend.md`, but the trace still requires every lower layer to be exactly one commit, so a `./zn commit` on a finished lower layer now lets `./zn start` open the next layer on a stack the trace will refuse. The design's list of readers was also wrong (it named `finish` and `restack`, which do not read the rule).

**How to apply:** grep for every reader of the function and of the state it decides; write the list from the grep, not from memory. For each pair of judges, state where they agree and where they differ after the change, and either make them agree or put the differing state, its message and its recovery in the design and the skill.

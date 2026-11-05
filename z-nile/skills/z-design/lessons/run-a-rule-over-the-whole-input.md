---
title: A selection rule is run over the whole input and its answers counted
when: design
tags: [experiments, selection, measurement]
check: Over today's full input, how many items does this rule select or hold, and why each, before the design relies on it?
---
A rule tried on three examples can select almost everything, or almost nothing, over the real input.

**Why:** c0112 design review 002 F5: the "held" rule built on `./zn busy` was tried on three folders; over the tree it held nearly every item (it names every active raft for any path, and stale prototype branches "change" about 128 `done/` folders).

**How to apply:** run the rule over the whole set in prep, record the count and the reason for each selection in the Unknowns, and fix the rule if the count is not what the design needs.

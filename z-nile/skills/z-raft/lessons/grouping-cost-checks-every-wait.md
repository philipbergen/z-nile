---
title: A "grouping costs nothing" claim checks every member's wait
when: design
tags: [raft, order, dependencies]
from: R0065 design review 001 F1 (the reviewer's candidate lesson)
check: When the Order says grouping costs the dependents nothing because they wait for X anyway, does every member's unfinished `depends_on` appear among the dependents' own waits, or is there one (and its unfold fallback) the claim leaves out?
---
A raft starts only when every member's `depends_on` is done, so items that depend on one member wait for all of the raft's waits, not only the one the Order names.

**Why:** R0065 design review 001 F1: the Order said grouping cost f0158 and c0182 nothing because they wait for f0126 anyway, but c0170 also waits for c0153 (R0059), which neither needs.

**How to apply:** list each member's unfinished `depends_on` against each dependent item's; name every wait the dependents do not share, and say which member to unfold if it lags.

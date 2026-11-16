---
title: A case that needs the live jail returns off-host, and check.sh proves it ran
when: design
tags: [specs, jail, promotion, check-sh]
check: Under each PICKMAN_TEST_JAIL value (sandbox-exec, outer sandbox, none, bwrap), what does each case of this spec do after promotion, and what in check.sh fails if the jailed branch never ran?
---
A sequestered spec that `error`s off `sandbox-exec` keeps its own check honest, but once promoted it reddens every Linux, outer-sandbox and jailed-clone gate, including another raft's CI.

**Why:** c0194 design review 005 F1: `runner.spec`'s live case called `error` when not jailed. Promoted, it would have failed c0075's Linux CI gate (which lands after it) and every jailed clone. c0076 already had the shape: the case returns when unjailed and writes a marker when it ran, and `check.sh` requires the marker on Darwin.

**How to apply:** return after asserting which kind of run it is; write a marker under the case's own `.cache` folder when jailed; make the item's `check.sh` require the marker on Darwin ("run this check outside any other sandbox"); tell the prepared raft that lands later.

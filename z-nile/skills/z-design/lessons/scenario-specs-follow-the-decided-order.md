---
title: Scenario specs run events in the order the user decided
when: design
tags: [specs, scenarios, order, decisions]
check: When a user decision fixes an order of events (the next layer exists and blocks, then the green layers below it land), does each scenario spec run that order rather than a reordering that is easier to set up, and is every reordering justified in the Test plan?
---
A fixture that sets up events in a convenient order can hide the defect the decided order produces. The decided order is the one the tool will meet.

**Why:** c0248 design review 001 F3: the AC7 case sealed layer 2 before cutting layer 3, the one order the user's "They merge now" never produces; in the decided order the second bind hit an add/add conflict on `trace.md` and no command could repair it.

**How to apply:** for each user decision that orders events, write one scenario that follows it step by step, and name any other order the specs use and why.

---
title: A decision that makes a state always on can idle what grants it
when: design
tags: [scope, decisions]
check: When a user decision makes another feature's state always on (or always off) on some levels or modes, which rolled or granted things set that state, and does any become a no-op there? Has the user been told where and chosen?
---
Turning a state on for good silently empties every reward that only turns it on.

**Why:** f0147 design review 003 F2: the user's bonanza gives long hops for the whole next level, and every level ends with a bonanza, so from level 2 on the rolled "longer jumps" boon (one roll in six) grants nothing. The prep had recorded the always-on long hops but not the idle boon; the user chose "Keep it, record it" once asked.

**How to apply:** for each decision that fixes a state, search the design and game-design.md for everything that sets that state, list where it becomes a no-op, and put that to the user with the options (keep and record, re-roll, another reward).

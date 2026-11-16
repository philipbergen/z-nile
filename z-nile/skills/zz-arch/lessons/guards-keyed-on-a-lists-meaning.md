---
title: A guard keyed on an existing command list inherits that list's meaning, not the guard's
when: design
tags: [guards, commands, lists]
check: Does the list this guard exempts by say the same thing the guard needs (its own comment: "reads only" versus "may run without git"), and is every command and form decided for this guard, with its reason?
---
Reusing a list that happens to exist (`READ_ONLY`, "may run in a git-less sandbox") for a new guard ("may run over a merge conflict") exempts the wrong set: commands that only read but aren't on the list are refused, and the list's next edit for its own reason silently changes the new guard.

**Why:** c0139 design review 001 F1: the conflict guard exempted `READ_ONLY`, so `busy`, `capture`, `lessons`, `status <id>` and `raft-plan` refused mid-merge although they only read, contradicting the design's own Non-goal.

**How to apply:** give the guard its own list, decided command by command (and form by form: `status <id>` reads, `status <id> <to>` writes), each with a reason, and a case per form; leave the old list to its own purpose.

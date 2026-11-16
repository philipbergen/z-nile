---
title: A deviation's recorded cause is checked with git log before it blames another raft
when: build
tags: [verification-log, deviation]
check: Does `git log origin/main -- <file>` show the change the Verification log blames, or did I guess the cause from the error text?
---
A deviation entry is read later as fact. Naming the wrong cause (another raft that never touched the file) sends the next reader to the wrong place.

**Why:** R0075 review 001 F2: the log said R0079 had made `skills.plan` return two values; `skills.luau` had not changed since R0049. The patch itself passed `load`'s two return values to `plan`.

**How to apply:** before writing "X changed Y" in a log, run `git log origin/main --oneline -- <file>` and read the commit that is named; otherwise say "cause not established".

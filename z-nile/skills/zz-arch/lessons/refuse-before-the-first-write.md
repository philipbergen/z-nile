---
title: Every refusal a later step can raise is decided before the first step publishes or moves anything
when: both
tags: [refusals, rollback, publish]
check: For a command that works in steps (publish a claim, merge, write a file, move folders), which inputs make a later step refuse (a record that does not parse, a bad actor), and is each checked before the first step, with a case that leaves origin and the tree as they were?
---
A command that publishes first and writes second leaves a half-done state when the second step refuses: the claim is on `origin/main`, a staged line is in the worktree, and the user is left to `release` or `git reset --hard`.

**Why:** c0282 design review 001 F5: `fold` published its claim and then failed on a member record that did not parse; `done` failed after moving every folder with no rollback. The design promised refusal before anything is published for a bad actor only.

**How to apply:** call the later step's own check (parse the record it will append to) at the top, beside the other refusals, and add a case per command that feeds it the bad input and compares origin's tip and `git status`. A step that can still fail after the check rolls back.

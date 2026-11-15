---
title: Work added to every command is timed and its doomed starts counted
when: both
tags: [performance, hooks, processes]
check: For each step a hook runs at every command, how many processes and milliseconds does it add (measured, not read), and which of its starts can never succeed and how many are paid before something stops them?
---
A step that is cheap once is paid by every `./zn` command in every worktree; a repeated question (is this the main checkout?) costs a git call each time, and a start that cannot succeed (a claim ended elsewhere) costs an engine start per command.

**Why:** R0100 review-005 F3. The automatic beat asked `inMainCheckout()` (two git calls, 56 ms with 98 worktrees) five times per mark per command, and started a beater that failed at once for every command until the mark's next due beat.

**How to apply:** ask once per process (the memo), put the cheapest test first (`kill -0` before `ps`), time a command with ten runs through `./zn run`, and when a start can be doomed either skip it until its mark is due or say in the design that it is paid.

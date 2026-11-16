---
title: A golden diff read from the merge base with origin/main puts its item below every raft member that changes the file
when: design
tags: [acceptance, golden, rafting, order]
check: For each golden diff this item's checks read from `git merge-base HEAD origin/main`, which prepared or active items also change that file, and does the design state that this item sits below them in any raft (and does a step refuse a branch where a commit of another member changed the file below it)?
---
A check that compares `git diff $(git merge-base HEAD origin/main) -- <file>` with a golden assumes that nothing between `main` and this item's own commits changed the file. On `main` that holds whichever item lands first (leave the hunks' `@@` lines out, so a change above a hunk does not move it). In one raft's stack it does not: a member layered below that changed the same file shows up in this item's diff, and since the check is sequestered, a red one stops the raft for a re-prep.

**Why:** c0287 design review 001 F4: c0250 (prepared, no raft) changes control-cli's first cases; layered below c0287 in a scratch stack, c0287's AC3 read c0250's hunks too and went red (94 lines). "Either may land first" was true for main only.

**How to apply:** list the other items that change each pinned file (their `prototype.patch` and Touched modules), state in Existing work that this item sits below them in any raft (z-raft reads it), and have step 0 check `git log origin/main..HEAD -- <the files>` lists only this item's commits before the golden check runs.

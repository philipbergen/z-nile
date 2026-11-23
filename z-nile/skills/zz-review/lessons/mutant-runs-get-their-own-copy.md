---
title: A reviewer that applies mutants works in its own copy
when: both
tags: [review, mutants, worktree]
check: When a review edits source to try mutants, does it run in its own detached worktree, so that no other reviewer, builder or gate reads the mutated files?
from: code and test reviews of d0434 and f0420-claim-expiry, 2026-11-22
---
A mutant is a deliberate bug in the working tree for as long as its run lasts. Anything else reading that tree in that time sees the bug.

**Why:** 2026-11-22: the code reviewer and the test reviewer of d0434 shared one worktree; the test reviewer's mutants made the code reviewer's spec runs fail, and it reported results that said nothing about the branch. The same day a stopped reviewer left a mutant in the claim-expiry worktree (a heartbeat allowed to start the daemon), found only because the lead looked at the diff.

**How to apply:** the brief tells a mutating reviewer to make a detached worktree of the commit, work only there and remove it at the end; the lead checks git status of the real worktree before any gate.

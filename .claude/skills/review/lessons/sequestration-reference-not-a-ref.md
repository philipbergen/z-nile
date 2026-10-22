---
title: A sequestration check never takes its reference from a ref the author can move
when: both
tags: [sequestration, guards, review]
check: Can the branch's author make the reference commit (a local or pushed branch, a merge) that this check judges sequestered files against?
---
A check that compares sequestered files with "the newest prep commit merged into the branch" lets the author pass it: point a local branch of that name at HEAD, or push an edit to the prep branch and merge it, and the edited `check.sh` becomes its own reference.

**Why:** c0120 code review 004 F1. AC18 read `origin/prep-c0120` and `prep-c0120` to find c0120's own files' reference after Guess 17's decision reached the item folder by a prep merge. In a clone, `git branch -f prep-c0120 HEAD` turned a deleted AC18 line green. The user decided "Reviewer-pinned commit": the reference is a `Prep reference: <sha>` an approving review records, and a missing or foreign sha refuses.

**How to apply:** when a check needs a moving reference, take it from a file only a reviewer writes (an approved review's recorded sha), never from a branch name, and refuse when it is missing or not in the branch. Add the case that moves the ref and expects red.

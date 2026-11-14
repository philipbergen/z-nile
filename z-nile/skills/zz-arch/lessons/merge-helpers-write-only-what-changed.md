---
title: A merge helper writes only what changed and never over uncommitted work
when: design
tags: [git, merge, data-loss]
check: Before this helper writes or removes a file in the middle of a merge, does it compare the text with what the merge already holds, and does it stop when the path has uncommitted changes (or is untracked) instead of overwriting them?
---
A helper that finishes a merge by rewriting files on disk can lose work git would have kept: git leaves a path it did not touch alone, and refuses a merge that must touch a dirty one. Rewriting every file the helper settles (including the ones the merge never touched) silently discards an uncommitted edit.

**Why:** c0263 design review 012 F2: `mergeRef` wrote the settled record over a worktree file whose only difference was an uncommitted row; the sync exited 0 with a clean status and the row was gone, where plain `git merge` kept it.

**How to apply:** write only when the settled text differs from the merged index's entry at that path; before writing or removing a path the merge did not leave unmerged, stop when it has unstaged changes or is untracked, naming it (and give the advice that fits whose merge it is: a merge the helper started is aborted by a stop, a user's hand merge stays in progress, so a stash would discard it). Decide every write first and apply them after, so a stop leaves the tree as it was. Cases: an uncommitted row survives; a stop on an unstaged edit and on an untracked file at the destination.

---
title: An item named in a step's worktree is found through that worktree's own registry, never the process's checkout
when: both
tags: [dispatch, worktree, store, spend]
check: For each lookup of an item that a step's worktree may hold before its pull request merges, which checkout does the reader resolve against, and does that checkout hold the item yet?
---
`store.get` resolves through the checkout the process runs in. A dispatcher started in the main checkout does not see a raft that exists only in the step's `raft-<slug>` worktree.

**Why:** R0136 code review 001 F2: `record` found a raft's members with `store.get`, so z-raft's own prep row of a new raft stored no members, was never written, and `dispatch status` blamed a row "recorded before d0415".

**How to apply:** read an item in a step's worktree with `costrow.locate(cwd, id)` and the document beside it; when it is not there, say so on the refusal instead of treating the row as old; add a case that runs the step from the main checkout with a document only the worktree holds.

---
title: A rollback that discards a commit also keeps what the commit consumed outside git
when: both
tags: [rollback, retry, spend, cache]
check: What does this commit read and then remove from ignored state (the measurement buffer, a claim file, a cache), and does every path that discards the commit (a rollback, a retry) keep it for the next attempt?
---
`git reset --hard` undoes the tree, not the ignored files a command changed while making the commit. Whatever the commit folded in from such a file is gone with it unless the command keeps it.

**Why:** d0331 design review 001 F5: the binding commit folds the gate's measured line out of `.cache/measure.tsv` into the ticket's `spend.d` rows and rewrites the buffer without it. A done that rolls back discards that commit, and the next attempt's line is keyed to another head. One lost gate per failed done was already true; a retry loop of up to nine attempts would have made it routine, and zz-stats would never have seen the cost.

**How to apply:** list what the commit takes from ignored state. On each path that discards the commit, either put it back where the next attempt will take it, or carry it in memory into the next attempt (d0331 passes the folded rows to the next `recordAndCommit`). Add a case that counts the rows after a discarded attempt.

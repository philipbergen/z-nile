---
title: A reader that runs one git process per event grows with the history
when: design
tags: [git, scalability, readers]
check: For each git process a reader runs, what is it per (item, commit, merge, file), and does the count stay constant as the history gains a raft per week? Is the per-event read one `--stdin`/`--no-walk` or `--batch` process?
---
Batching the reads per item leaves the reads per event: one `git log -1` per merge costs nothing in a fixture with one landing and 2.4 s on fifty, and every raft landed since #296 adds a merge to every build.

**Why:** c0284 design review 001 F6: `who.sideTrailers` ran a `git log -1` per merge commit; measured 50 of them 2.35 s, one `git log --no-walk=unsorted --stdin` over the same commits 0.10 s.

**How to apply:** read all of a kind in one process (`git log --no-walk=unsorted --stdin`, `cat-file --batch`), set the results on every copy, and have the spec count the process by its own arguments with a fixture that holds more than one event (two landings, not one).

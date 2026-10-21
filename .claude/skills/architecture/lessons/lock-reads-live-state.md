---
title: A lock reads state that changes when the guarded thing changes
when: design
tags: [concurrency, claims, state]
check: Does every claim or hold read state that is updated at the moment the claimed thing changes, rather than state that only catches up later (at a merge, a sync or a rebuild)?
---
A hold that is computed from data published later than the change it guards is stale exactly while it is needed. Each patch to one command then leaves another command that reads the same stale data, and review rounds keep finding new holes.

**Why:** R0042 design reviews 002 F4 to 005 F2 (six findings over four rounds): c0116 computed "who holds a prepared issue" from origin `issues:` lists, which change only when a prep PR merges, while membership changed in the worktree. Every round patched one command (`new raft`, the carried move, `recombine`, the give-back), and the next round found another.

**How to apply:** name the moment the guarded state changes, and make the lock live there: the line both writers edit, so that git conflicts, or a published stamp written at that moment. When a third round finds a hole in the same lock, redesign the lock instead of adding a row.

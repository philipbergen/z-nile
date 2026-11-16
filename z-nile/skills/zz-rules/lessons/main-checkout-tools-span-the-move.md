---
title: Tools run from the main checkout work on trees from both sides of a move
when: design
tags: [migration, hooks, worktrees]
check: Does every hook or tool that the main checkout runs against another worktree (the stop hook, a session's checks) work on a tree from before this change as well as after it, until the old trees are gone, including trees between two markers (it has the old marker but not the helper the hook now calls) and a helper that is broken mid-edit, with any unusable answer falling back to the old call?
---
The main checkout always has the newest tooling, but its hooks act on whichever worktree a session is in, and that tree may predate the change. A hook that calls a path only the new layout has blocks every session in an older worktree, and an active raft may not be able to merge `main` mid-stream to escape it.

**Why:** R0043 design review 001 F2: the stop hook was moved to call the gate at its new path, which no worktree from before the move had, so R0034's sessions would have been blocked at every stop.

**How to apply:** for each hook or tool the main checkout runs, call a path both kinds of tree have (the forwarder at the old path, while it exists), or choose by what the tree holds. Add a spec that runs it in a fixture tree of the old layout. Name the switch to the new path in the raft that removes the forwarders.

**Also:** c0165 design review 005 F1: the stop hook fell back only for trees without `z-nile/roots.luau` (c0114), so every tree between c0114 and c0165 answered `--gate-projects` with `ALL` or spec paths, which the hook passed on as project names. Detect the feature the hook is about to call (the helper's file), validate its answer, and take the old call on any answer it can't use.

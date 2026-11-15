---
title: A path allow-list over commits accepts every file the prescribed command writes
when: both
tags: [allow-list, commit, finish, trace, spend]
check: For each rule that allows only named paths in commits after some point, which command do the skills tell the agent to commit with there, and is every file that command writes on the list?
---
A rule that judges commits by the paths they touch (what may follow a finish commit, what may follow a trace table) is only as wide as its list. When the command the protocol prescribes for those commits writes a file the list leaves out, every agent that follows the protocol is refused.

**Why:** R0102 final review 001 F1: zz-execute Phase 5 says to commit `trace.md` and the final review with `./zn commit`, which rewrites the raft's `spend.md` on every commit. `layergit.isPostFinishPath` and trace's two lists allow `spend.d/` but not `spend.md`, so the finished layer read as not finished, `./zn trace --check` called the table stale and `./zn done` would refuse. d0333 owns the fix.

**How to apply:** in the design, run the prescribed command once after the point the rule guards (on a prototype or a fixture) and compare `git show --stat` with the list. In a spec, make the fixture's post-point commit with that command, not with plain git.

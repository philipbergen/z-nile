---
title: A detached process does not live in its starter's folder
when: design
tags: [net, detached, worktree]
check: For each process that outlives its starter, which folders and programs does it read after the starter's worktree is removed, and does a spec remove that worktree while the process still has work to do?
---
A process meant to outlive its starter must not depend on the starter's checkout once it has started: its cwd, its `ZN_TOP`, the `zn` it runs. The worker removes a raft's worktree minutes after the kick.

**Why:** d0383's first build (R0138, 2026-11-19) ran the watch net from the worktree that kicked it. A rerun requested by a second landing started after that worktree was gone: `<deleted>/zn` threw, the net exited 1 and left its lock, and the request was already consumed, so the second landing was never tested (code review 001 F1, reproduced by a probe). The design review had moved the log out of the kicker's worktree for the same reason and not asked the question of the process itself.

**How to apply:** Resolve the long-lived place (the main checkout, a standing worktree) once at the start, give every later command an explicit cwd there, and run the long-lived place's own program for later steps. Add a case that removes the starter's worktree while the detached process is held mid-work. Close to zz-test/detached-helpers-meet-the-reaper, which asks the same of the reaper.

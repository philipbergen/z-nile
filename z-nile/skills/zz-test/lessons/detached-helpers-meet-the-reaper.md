---
title: A process a command starts to outlive it is run past the reaper before review
when: design
tags: [reaper, processes, background, bounded]
check: For each process this design starts so that it outlives its starter, was it started the way the real command starts it, left for a minute, and judged by `./zn reap --dry-run`; and does `./zn run` still hold it (it stops its command when its starter dies)?
---
A helper that must outlive the command that started it is a leak by the reaper's rules (a parentless `perl`, `sh` or `lune` older than a minute in a worktree) until the reaper is told otherwise, and `./zn sync` runs the reaper.

**Why:** c0275 prep (2026-11-12). The "background beater" of the heartbeat is `./zn run --time 3600 -- ./zn beat <id> --watch`, started by a claim and gone from its starter at once. `./zn reap --dry-run` on the same shape at 68 s said `would stop ... orphaned (its parent is gone)`; and a plain `./zn run` started by a command that exits is stopped by the runner itself, because it polls its parent. The marker the reaper reads (`ZN_BOUNDED_DEADLINE`) cannot be read from `perl` on macOS, so the exemption had to read the command line.

**How to apply:** start the helper from a tool shell the way the engine will (double fork, new session, runner `exec`ed after it has a new parent), wait past `--min-age`, run `./zn reap --dry-run`, and put the shape in a pure case of the reaper's rules. The wait for the reparent compares `getppid()` with the starter's own pid (`$$`), not with the starter's parent, and the helper exits if the reparent never comes; probe the loop under load, because a spec cannot see the race.

**Note** (c0253 prep, 2026-11-16): a process meant to outlive its starter needs the reaper to know it. c0253's detached supervisor was listed by `./zn reap --dry-run --min-age 0` as an orphan it would stop, which led to `reap.isSupervisor`. Its re-exec also ran a bare `work` and printed the skill, because the detached argv lacked the subcommand marker (`work run`). Ask: does the dry-run reaper list it, and does the detached argv re-enter the right command?

**Also** (c0253 revision): exempting a process by its recorded pid must also cover its launcher shim and its own helpers. c0253's supervisor held its lock through a perl child, which the reaper would have stopped after a minute, releasing the lock under a live supervisor. A tool's PATH shim (rokit's `lune`) also makes two processes of one command.

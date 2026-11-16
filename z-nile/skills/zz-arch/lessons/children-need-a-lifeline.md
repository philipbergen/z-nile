---
title: A child in its own process group needs a lifeline, and a stored-pid kill checks identity
when: design
tags: [process, supervision, safety]
check: What happens to the child when the parent dies (Ctrl-C, a crash, a closed terminal, or a SIGKILL of the parent's whole process group), what is left alive to notice it (a supervisor in the parent's own group dies with it), and what does a stored pid or group id name after the process is gone and the number is reused?
---
A child the tool starts with `setpgrp` (so one signal can stop its whole tree) leaves the terminal's foreground group: Ctrl-C, a closed terminal or a crash of the parent leaves it running with nothing enforcing its limits. Give it a lifeline: a supervisor whose stdin is a pipe from the parent kills the group on end of file, and on its own TERM. A later kill by a stored pid or group id must first check that the id still names the same run (a lock the supervisor holds for as long as the group lives, or a start time and command line), refuse an id of 1 or less (`kill -- -1` signals every process the user owns), and mark the run lost rather than signal a stranger.

**Why:** c0117 design review 001 F4: the dispatcher's step outlived a killed dispatcher with no cap, `stop` signalled `-<pgid>` from stale state with no identity check, and two dispatches of one item could run at once.

**How to apply:** a supervisor with a lifeline; an flock-held run lock (a dead holder releases it at once, and `ps` may not be allowed where specs run); spec cases that kill the parent mid-step, stop a stale state whose id now names a live process, refuse a group id of 1, and refuse a second run.

A supervisor that watches its parent must lead a process group of its own: in the parent's group, a kill of that group takes the supervisor down too, and its watch never fires (c0165 design review 002 F1: the runner, in a group of its own, outlived a `kill -9 -- -<pgid>` of the orchestrator's group and held the home's lock).

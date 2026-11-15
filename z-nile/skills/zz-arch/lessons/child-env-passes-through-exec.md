---
title: A value meant for child processes goes in the exec's env, never in a process.env assignment
when: both
tags: [lune, env, processes, runner]
check: Does every value this code means a child process to see reach it through the `env` option of the `process.exec` that starts it (or the child's argv), rather than through a `process.env.X = ...` assignment, which Lune 0.10.5 does not pass to children?
---
In Lune 0.10.5 (the version `rokit.toml` pins), `process.env.X = v` changes only the Lune table: a child started afterwards, with or without an `env` option, does not see X.

**Why:** c0230's prep (2026-11-15): `fence.enter` assigns `process.env.PICKMAN_WORKER_LANES` before it starts the jailed run, and the coordinator inside the jail read nil, so a top-level run never used the shared worker lanes and a CPU measure built into the lane wrapper would have measured nothing. Probe: `process.env.ZN_PROBE_FOO = "x"; process.exec("sh", {"-c", "echo [$ZN_PROBE_FOO]"})` prints `[]`. Captured as c0352.

**How to apply:** pass the value in the `env` table of the exec that starts the child (it is inherited from there down), and pin it with a case that reads the value in a grandchild of a top-level run, never by setting the variable in the spec's own env.

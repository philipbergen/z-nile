---
title: Every probe you start is time-bounded and dies with you
when: both
tags: [process, probes, experiments, review]
check: Does every command I start outside the spec runner (a probe, an experiment, a scratch run, a loop, a background job) stop on its own within a minute, and when I stop?
---
Run every probe, experiment, loop and background command you start yourself (anything that is not the gate, a check, a `./zn` command or the spec runner) through `./zn run --time <seconds> -- <command>`: it stops at its limit, when it ends and when you do.

**Enforced by** `z-nile/tests/meta/bound-every-probe.spec.luau` (in the gate), `z-nile/lib/bounded.pl` (the runner), `scripts/hooks/pre-bash.sh` (the hook), `z-nile/engine/reap.luau` (the reaper), `AGENTS.md` and `z-nile/tests/acceptance/c0191/docs.spec.luau`.

**Why:** a code review of PR #125 fed hostile `check` lines to `raftcheck`; three hit an infinite loop (c0193) and ran 14 h at 100% CPU on three cores, after the session ended. An `alarm` then `exec` is no bound: it kills only rokit's `lune` launcher and leaves the real `lune` spinning.

**How to apply:** write the probe as `./zn run --time 60 -- <command>`; a command known to run longer (`runtime-test`, a mutation run) gets the limit its step names, never an open one. Never get round the hook with `&`, `nohup` or `setsid`. A probe that exits 124 (wall clock) or 125 (CPU) has found a hang: report it, don't raise the limit.

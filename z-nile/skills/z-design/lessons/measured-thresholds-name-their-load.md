---
title: A threshold chosen from a measurement says the load it was measured at, and is remeasured at a gate's load
when: design
tags: [measurement, budgets, load, defaults, questions]
from: c0230 prep note (the F3 ruling, E13) (ticket withdrawn 2026-11-16)
check: For each default or limit this design picks from a measured number (CPU, wall, files), what was the machine's load when it was measured, and was it measured again at a busy gate's load before the option's cost was put to the user?
---
CPU per process rises with load as wall time does, only less, so a number from a quiet machine understates what a gate sees.

**Why:** c0230's F3 put a 3 s per-file CPU default to the user as listing "four z-nile files today", measured at light load. Rerun at load 5 to 16 after the ruling, the same suite listed 13 files, the heaviest at about twice their light-load CPU (c0230 E13). The cost quoted for the option was wrong by a factor of three.

**How to apply:** record the load (`uptime`) beside every measurement a threshold rests on, measure the option's cost at least once at a typical gate's load, and quote the range, not the best case, in the question to the user.

**Note** (c0178 design review 005 F12, 2026-11-24): AC2 pinned absolute limits (today's simulation numbers times 1.15, with pass counts 23, 22 and 18) on three spec files other rafts keep editing, under time limits the gate queue (up to 1,800 s) can use up, on the machine whose load is the ticket's reason. Check: is the checked number the mechanism's (a check-only probe of N fixtures against one build plus N times a budget, a ratio against the base measured in the same check), and does each run's time limit cover `ZN_GATE_WAIT`?

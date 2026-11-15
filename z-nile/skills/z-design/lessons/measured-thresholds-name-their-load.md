---
title: A threshold chosen from a measurement says the load it was measured at, and is remeasured at a gate's load
when: design
tags: [measurement, budgets, load, defaults, questions]
check: For each default or limit this design picks from a measured number (CPU, wall, files), what was the machine's load when it was measured, and was it measured again at a busy gate's load before the option's cost was put to the user?
---
CPU per process rises with load as wall time does, only less, so a number from a quiet machine understates what a gate sees.

**Why:** c0230's F3 put a 3 s per-file CPU default to the user as listing "four z-nile files today", measured at light load. Rerun at load 5 to 16 after the ruling, the same suite listed 13 files, the heaviest at about twice their light-load CPU (c0230 E13). The cost quoted for the option was wrong by a factor of three.

**How to apply:** record the load (`uptime`) beside every measurement a threshold rests on, measure the option's cost at least once at a typical gate's load, and quote the range, not the best case, in the question to the user.

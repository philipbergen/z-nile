---
title: A fixture's stall limit is one only a stuck step reaches
when: design
tags: [stall, load, fixtures, models-toml]
check: Does every `.models.toml` a spec's fixture writes set `stall_seconds` (and `tool_seconds`) at 120 s or more, unless the case tests a stall, and does that case then say so with its own closer, short limit and a stub silent for well over it?
from: c0288 prep note (c0288 withdrawn 2026-11-16)
---
The dispatcher's runner charges every tick it is starved to the step as silence, so on a loaded machine (load 47 to 97 on 18 cores) a stub that prints at once can still pass a short silence limit and be killed as `stalled`. A fixture's short limit is a load-dependent red, not a faster failure.

**Why:** c0279 (c0117's dispatch spec at 2 s, red under load until it moved to 120 s), and c0288: c0260's specs were written at 5 s, then at 30 s, the same bet at longer odds; a stub silent for 35 s, a slow machine simulated, fails at 30 s and passes at 120 s.

**How to apply:** set `[dispatch] stall_seconds = 120` in a spec's fixture; only an issue whose cases test a stall gets a closer `.models.toml` with a short limit (c0279's c0040, 10 s, its stubs silent for 20 s). A stub that must be quiet while it works belongs to a fixture with the long limit. To prove it, delay the stubs' first output past the old limit and run the spec at the new one.

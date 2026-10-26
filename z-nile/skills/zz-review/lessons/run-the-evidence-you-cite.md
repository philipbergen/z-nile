---
title: Run each claim in a finding's evidence, never infer it from the code
when: build
tags: [review, evidence, probes]
check: Did I run each claim in my Evidence (a command, its output), or did I infer it from code I read? And on a re-review, did I re-run the previous round's evidence for every claim a fix rests on?
---
A finding whose evidence was read from the code rather than run can describe behaviour that doesn't exist, and the fix then builds on it.

**Why:** R0050 code review 003 F3 reported that the bare `status` listed a retired raft as `prepared` without running it. `publish.allowed` never accepts a `rafts/retired/` path, so the bare `status` never listed it at all. The fix added a `retired` branch there that can't be reached, and review 004 F2 found it dead.

**How to apply:** for every behaviour a finding states, run it in the scratch clone and quote the output. On a re-review, re-run the previous round's evidence for each claim its fix rests on before ruling the fix good.

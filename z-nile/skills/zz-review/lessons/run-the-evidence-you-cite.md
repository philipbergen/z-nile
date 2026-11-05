---
title: Run each claim in a finding's evidence, never infer it from the code
when: build
tags: [review, evidence, probes]
check: Did I run each claim in my Evidence (a command, its output), or did I infer it from code I read? And on a re-review, did I re-run the previous round's evidence for every claim a fix rests on?
---
A finding whose evidence was read from the code rather than run can describe behaviour that doesn't exist, and the fix then builds on it.

**Why:** R0050 code review 003 F3 reported that the bare `status` listed a retired raft as `prepared` without running it. `publish.allowed` never accepts a `rafts/retired/` path, so the bare `status` never listed it at all. The fix added a `retired` branch there that can't be reached, and review 004 F2 found it dead.

**How to apply:** for every behaviour a finding states, run it in the scratch clone and quote the output. On a re-review, re-run the previous round's evidence for each claim its fix rests on before ruling the fix good.

c0121 design review 004 F3: round 003 inferred from the code that a dispatcher killed mid-step recorded its outcome before dying; a scratch run showed the write to the closed pipe comes first, so the state stays `running`. Run a claim about what a failure path writes (which line fails first, what is saved) before ruling on it, and before a refute adopts it.

**Note** (c0121 design review 005 F1): a Recommendation that moves an anchor (a base, a pinned sha, a range start) must be replayed against every rule that reads that anchor before it is written. Round 004 recommended "have the rebase record the base sha"; the refute took it word for word, and the moved base hid the landings the zero-match rule searched for. List the rules that read the anchor and run each with the moved value.
f0109 design review 003 F1: review 002 F1 prescribed the radar's state list (F,F), (F,T), (T,T), and it left out (T,F), the game's real flash; the author followed it, and two wrong adapters passed. A Recommendation that lists cases is evidence too: check each listed case against what the real producer emits before prescribing it.

f0109 design review 004: main had moved under files the specs load (c0128 narrowed two fake-engine specs) since the prototype's base, so the reviewer applied the prototype to today's origin/main and re-ran there. On a re-review, run the evidence against today's origin/main, not only the prototype's base, whenever main changed a file the specs load.

c0153 design review 003 F1: the design said Lune's encoder keeps 16 digits; measured apart, the encoder writes the exact shortest text and the decoder loses the ulp. When a spec or a design explains the cause of a numeric difference, measure each step (the encode, then the decode) on its own before naming which one loses precision, with the tool version the project pins.

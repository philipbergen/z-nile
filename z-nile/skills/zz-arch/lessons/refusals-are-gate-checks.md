---
title: A refusal any one tracked file can trigger is also a gate check
when: design
tags: [guards, gate, recovery]
check: Can a pull request that triggers this refusal pass CI, or does the gate run the same check against the merge base so a clean main stays green? If one lands anyway, where is the recovery written, and does it work while the tool refuses?
---
A guard that fails closed on the contents of a tracked file (a committed conflict, a bad registry) stops the whole tool in every checkout once one such file reaches main, and the tool's own commands can't fix it because they refuse.

**Why:** c0139 design review 001 F4: one quoted whole conflict in any document under a root would stop `sync`, `land`, `new` and `commit` everywhere, and nothing stopped such a PR from landing.

**How to apply:** report the same condition from a check the gate runs (here `audit`'s `conflict-markers` error), and write the recovery (plain git, a PR made without the tool) in the refusal itself.

---
title: Specs and Design correspond one to one
when: design
tags: [acceptance, rules-and-mutants]
check: Does every behaviour the Design states have a spec case that fails without it, does every sequestered assertion follow from a Design sentence, and does every check's label say exactly what its command verifies? Is each new case's recorded mutant killed by that case itself, not first by an older, stricter case (delete the case: does its row's mutant still die)?
---
Sequestered specs and the Design must match in both directions. A stated behaviour with no failing case (a refusal, an output format, an order) can be implemented wrong. An assertion the Design never states (message wording, which stream) can fail a correct implementation that the executor may not fix.

**Why:** R0040 design review 1: F3 found four specified CLI behaviours with no case; F6 found assertions on unspecified message text and on the output stream; F9 found an exit check whose label promised more than its command checked.

**How to apply:** walk the Design sentence by sentence against the Rules table, then walk each spec assertion back to a sentence. Specify every message shape and stream that a spec reads. For specs that read prose (skill text), quote the exact sentences in the Design, then trace mechanically: every literal the spec searches for must appear in the Design or in the file as it is on `main` (R0040 design review 4, F3: four pinned phrases were only paraphrased in the Design).

R0044 design review 4 (F1): the Design said the `UpdateAsync` transform keeps the place of its last call, but both stubs ran the transform once, so no case could fail it. A stub of an engine call that may retry its own callback must be able to call it again on a changed value.

f0126 design review 011 F3: V9 (the gold moved near Inky) was killed first by the exact-gold case, so the record never showed the new CIE76 case could fail; the row now mutates Inky instead, which only the new case catches.

c0153 design review 002 F1, F2: `plain.roundTrip` "checks plain data, then compares the decoded value", and every case that reached the comparison expected `true`, so a `roundTrip` that compared `v` with itself, or returned `true` after the check, passed; and "a table reached twice is not a cycle" had no case, so a `seen` set never cleared passed. For each function whose cases all expect success at a step the Design names, add an input where the intended code fails at exactly that step (here `eps` 0 on the one-ulp value), and a case for each "is not" the Design states.

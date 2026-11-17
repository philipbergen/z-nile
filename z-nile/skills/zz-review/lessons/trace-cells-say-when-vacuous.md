---
title: A trace cell with nothing true to cite says so in words
when: build
tags: [trace, final-review]
check: In the filled trace.md, does every cell whose claim nothing implements or tests (an empty Judged list, an Observed criterion run by a person after the merge) say in words that it is vacuous or a proxy not yet run, rather than citing a line that only looks like evidence?
---
`./zn trace` turns every criterion line into a claim, including "Judged: None." and the Observed criteria a person runs after the merge, and `--check` wants every cell filled. A reviewer who fills those cells with the nearest spec or source line makes the table claim proof that does not exist.

**Why:** R0118 final review 001 F3 (f0145): AC9 was "None." and AC10/AC11 were OC1/OC2. There is no test or code that proves them, so the only honest cells were references labelled "vacuous" or "proxy, not yet run".

**How to apply:** in final mode, fill such a cell with the closest document or spec line and say in the same cell, in words, that it is vacuous (an empty list) or a proxy for a step a person has not yet run. Name an Observed step's proxy as a proxy in the final report too, so nobody reads the table as having run it.

---
title: Folding cases from several spec files into one is re-measured as one lane
when: design
tags: [specs, speed, lanes]
check: After a split or trim folds cases from several spec files into one, does any file now hold the load an earlier round split apart for speed, and is its time measured against a per-file budget?
---
One spec file is one runner lane, so folding cases together undoes an earlier fix that spread them across lanes.

**Why:** c0165 design review 007 F5: trimming the design folded 17 fixture-building cases back into `gate-reuse.spec`, which design review 002 F9 had split; it took 121.5 s on its own, and check.sh ran it twice.

**How to apply:** after any merge of spec files, time the result, re-split by mechanism when it exceeds the budget, and run each file once from check.sh.

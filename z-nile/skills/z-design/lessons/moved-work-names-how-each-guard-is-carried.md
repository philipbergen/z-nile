---
title: Moving work to another repository or process says how each guard comes along
when: design
tags: [guards, migration, design]
check: For work moved to another repository or process, does the design list what the replaced wrapper or command did (the terminal test for approve, the refusal list before landing, sequestered checks) and say where each of those guards lives afterwards?
from: f0427 and f0428 design review 001 F2, F3, F4 (2026-11-21)
---
A wrapper often carries guards nobody wrote down. Replacing it drops them silently.

**Why:** f0427/f0428 design review 001 F2, F3 and F4 (2026-11-21): the designs moved work out without saying how the terminal test for approve, the refusal list before landing, and the sequestered checks were carried over.

**How to apply:** read the old command's source, list every refusal and check it made, and give each a row: kept (where), replaced (by what), or dropped (and the human told).

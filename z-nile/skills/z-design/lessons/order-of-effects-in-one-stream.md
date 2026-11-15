---
title: An order of effects is pinned in one stream
when: design
tags: [specs, ordering, mutants]
check: For each "before", "then" or "first" in the Design (show, then ask; check, then write), is there a case that sees both effects in one ordered record (one output stream, one log) and fails when the two swap, and is the swapped order a listed mutant?
---
A case that only checks that both effects happened passes an implementation that does them in the wrong order. The order is often the outcome itself.

**Why:** f0339 design review 001 F2: approve must open the explainer page and then ask y/n, but the spec only checked that the opener was called and that the prompt appeared; a mutant that asked first and opened after the answer passed. The fix had the opener stub write a marker to the terminal, so its place before the prompt shows in the one stream `script` records.

**How to apply:** for each ordered pair in the Design, find a single record both effects write to (the terminal under `script`, one log file a stub appends to) and assert the positions. Add the swapped order as its own mutant row, apart from "never does it".

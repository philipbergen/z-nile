---
title: A member stacked on another cannot override or run its promoted specs
when: design
tags: [raft, overrides, promotion, stack, depends-on]
check: Does any member's `Overrides:` line, `check.sh` or spec name a promoted path (`tests/acceptance/<id>/…`) of another member of the same raft, or assume that member is already done?
---
An issue designed to land after its dependency treats the dependency as done: it overrides the dependency's promoted specs and may run them from `tests/acceptance/<id>/`. In one raft nothing is promoted until the single `./zn done`, and the raft's `check.sh` runs every member's sequestered specs on the final tree. Two members that pin opposite things about one file are then both run, and one is red whatever the file says.

**Why:** R0097 design review 001 F1 and F2 (2026-11-15, the day dependent issues were first stacked into one raft). c0189's `wiring.spec` pins the hook's first line as `#!/bin/sh`; c0123 requires `#!/bin/sh -p` and overrides that spec as if promoted; c0123's `check.sh` AC6 runs `tests/acceptance/c0189/wiring.spec.luau`, which does not exist before c0189 lands. The same shape appeared in R0093 (c0260 over c0247, c0250 over c0256).

**How to apply:** before stacking a dependent onto its dependency, grep the dependent's document, `check.sh` and specs for `tests/acceptance/<dependency id>` and for an `Overrides:` entry naming the dependency. If one is found, the pair cannot be stacked as designed: both go back to z-design to be designed as layers of one raft (the lower member ships the final behaviour and pin; the upper drops the override), or they stay in sequenced rafts.

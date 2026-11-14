---
title: A new refusal goes after the old ones
when: design
tags: [refusals, commands, promoted-specs]
check: When a command gains a new refusal, is it checked after the refusals it already has, and does each promoted spec that pins a refusal's text still see that refusal first?
---
Promoted specs pin which refusal a command prints for a given state. A new check placed earlier fires first on the same state and turns those specs red for no change in behaviour.

**Why:** c0248's prototype: `done` checked the layers' completion before the final review, and `c0001/tracker-lifecycle`, which expects "no review", went red; moving the layer check after the final-review check kept it green.

**How to apply:** add the new refusal after the existing ones, and list in the Design the order `done` (or the command) checks in.

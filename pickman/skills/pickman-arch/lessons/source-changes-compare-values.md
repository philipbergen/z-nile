---
title: A fold's source has changed when its values change, not when a new table arrives
when: both
tags: [input, adapters, state]
check: Where an adapter resets a fold because its source changed, does it compare the source's values, and which callers produce a new table with the same contents (a refresh, a re-render)? Does a spec hand back a new-but-equal table and assert that nothing is reset?
---
Comparing tables by identity treats every rebuild as a change. A view that rebuilds its layout table on every refresh then resets the fold on every refresh.

**Why:** d0149 design review 002 F1: Controls let every finger go when `buttons()` returned a different table, but HudView rebuilt `Touch.buttons` on every shot gained or fired and every life lost, so firing dropped both thumbs; the spec's stub always returned the same table, so nothing caught it.

**How to apply:** compare by value with a pure function (`Touch.same`), and give the adapter spec one case with an equal copy (nothing resets) and one with moved geometry (everything resets); a Rules row with the identity mutant.

d0149 design review 003 F2: the same review's fix covered Controls but not HudView's own knob reset, which still centred both knobs on every shot or life refresh: every consumer that resets on a rebuild compares values.

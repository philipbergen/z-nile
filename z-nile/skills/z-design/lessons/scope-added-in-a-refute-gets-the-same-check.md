---
title: Scope added while answering a round gets the check that round demanded
when: design
tags: [specs, scope, review]
check: Is any adapter or rule newly added in this round's answers checked by a mechanism the same or a previous round rejected for this item (source-text pins where a behaviour run was required)?
---
When a round replaces source-text pins with a behaviour run for one adapter, and the same round's answers add a new adapter (a user's scope decision), the new one tends to be checked the old, cheaper way: four wrong bodies then pass.

**Why:** f0109 design review 002 F1: review 001 F2 had made MazeView run on the fake engine; the user's scope decision added the danger radar's walls in the same round, and the answer pinned DangerHud by source text again; RX1–RX4 (always blue, no recolour, the state ignored, an own blue as a table) all passed.

**How to apply:** for each adapter or rule a round adds, use the mechanism the round settled on for its siblings (here: run its real source on the fake), and list the wrong bodies as mutants.

---
title: A recommendation that lets a check accept a state "until X" says what happens to items already past X
when: both
tags: [recommendations, cut-over, audit]
check: When my Recommendation lets a check accept something only until a point (not done, not landed, before ready), what does that check do to the items already past that point, and does the Recommendation say?
---
A reviewer who widens a check for a new state often bounds it with "until" a later state, to keep the widening small. Every item that reaches that later state then fails the check, often the gate's real-tree audit.

**Why:** f0417 design review 001 F1 recommended that c0260's audit accept a guess-mode Confirmation "on a marked issue whose raft is not done"; design review 002 F3 found that the first such ticket to land would then turn the real-tree audit, and every gate, red.

**How to apply:** for each bound in a Recommendation, follow one item past it and name what the check then says; prefer a bound that is a property the item keeps (marked, approved) over a stage it leaves.

---
title: Shown time follows the rule, and the rule names the time it decides
when: both
tags: [interpolation, ticks, adapters]
check: For a rule decided once a step but shown continuously, does the design say which slice of shown time each step covers, is the rule pinned to that slice (not to the step's end tick), and is the client's shown time computed by one pure function with the same clamps as the other blends?
---
The server decides once a step; the client draws a continuous blend between two snapshots. If the rule samples the step's end while the camera shows the whole step, the player is caught while visibly safe. If the adapter computes its own shown time, it drifts from the blend the rest of the scene uses (an unclamped alpha runs ahead on a late snapshot and jumps back on the next).

**Why:** R0035 design review 005: F2 found the airborne rule sampled at the end of each step, so the landing step was a catch while the eye was drawn over the walls for 81% of it. F1 found the camera's shown tick used `View.alpha` unclamped, unlike `View.interpolate`, so the eye overshot and juddered between snapshots, and the sequestered spec pinned the faulty form.

**How to apply:** write down "step N is shown while the shown tick runs from N - 1 to N" (or whatever holds), decide the rule at the middle of that span or argue otherwise, and add a spec that samples the continuous quantity across each step's shown span and compares it with the per-step rule. Put the shown-time computation in Logic next to the existing blend, with its edge cases (no previous snapshot, a stale one, NaN, alpha outside [0, 1]) as spec cases.

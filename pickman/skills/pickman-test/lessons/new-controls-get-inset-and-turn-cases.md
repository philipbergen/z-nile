---
title: A new on-screen control gets the inset and screen-turn cases its neighbours have
when: both
tags: [specs, hud, touch]
check: Is each new frame an adapter draws placed on a screen with a non-zero inset, and checked again after the screen turns, as the HUD elements before it are?
---
A frame placed once, or from a layout without the device's inset, looks right on the test's one plain screen and wrong on a notched phone or after a turn. The earlier elements' cases do not cover a new one.

**Why:** f0126 design review 006 F4: the PICK button passed with no inset and no re-layout, the same two defects T4f and T5a had already fixed for the pick bar. f0158 design review 001 F1: the danger ring's clearance ran six screens, all with zero insets, and left out f0029's short samples under a top bar, where the ring met the score and level blocks.

**How to apply:** give the new frame its own case on a screen with a side inset, then turn the screen (portrait, then landscape with the inset swapped) and check its place after each layout; add both mutants to the Rules table.

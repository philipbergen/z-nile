---
title: Measure where the time went before fixing a timing failure
when: design
tags: [timing, load, stall, experiments]
check: Before choosing a fix for a failure that appears only under load, was each phase of the failing window timed (start, first output, each beat), and does the fix cover the phase the measurement blames? Does a check delay that very phase, with the cases the fix claims to cover passing?
---
A fix chosen from a plausible story ("the fake's startup is slow") can cover a phase that costs a fortieth of the window and leave the real one alone; and a simulated delay placed after the fix's own coverage proves nothing about it.

**Why:** c0279 design review 001 F1: the first-line fix for a 2 s stall measured at about 0.04 s of the window under load 97.

**How to apply:** time the phases of the failing window in a probe run through `./zn run` (the log gets a high-resolution time at each point); prefer a fix that holds by construction (a limit only a real fault reaches) over one that shortens the window; inject the delay into exactly the phase the fix claims.

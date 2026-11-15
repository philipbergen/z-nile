---
title: A frame-rate case cuts time at real frame times and compares the game, not float timers
when: both
tags: [frame-rate, timing, specs, mutants]
check: Does the frame-rate-independence case cut time at real frame times (1/60, 1/30, an irregular pair) across a step that is not a binary fraction, a death wait and a Ready end, and does it compare the game's state (bodies, headings, states, scores, turns) with timers only within a tolerance, so that dropping the clock's tolerance fails it and the correct implementation passes it?
---
A case that cuts time only in binary fractions (1/64, 0.125, 0.5) on a 0.25 s step proves nothing about frame-rate independence: every sum is exact in floating point, so the clock's tolerance never acts and an implementation without one passes. Cutting at 1/60 but comparing the whole state with exact equality fails the correct implementation instead, because its float timers differ from the long run's by rounding.

**Why:** f0211 design review 001 F1: moves.spec's "however the time is cut" passed with the World's `EPS = 0`; the server advances on Heartbeat, whose dt is never a binary fraction.

**How to apply:** play one seeded game whole (in step-sized chunks) and again cut at 1/60, 1/30, 0.1 and a ragged pair, on a map whose step is not dyadic (Snake's map 2, 1/4.25 s), long enough for deaths and respawns; give the inputs at fixed marks from their own seeded draw; compare the fields that are the game exactly and the timers within 1e-6 s. Add the mutant "no tolerance" as a row.

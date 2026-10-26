---
title: A refusal's spec sits on both sides of its bound
when: both
tags: [specs, validation, bounds, mutants]
check: For each refusal, does a case accept the largest value the rule allows, refuse the next one, and accept a value that only a simpler, stricter wrong rule would refuse; which stricter rule would also pass my cases?
---
A spec that only refuses a value far over a bound, and accepts values far under it, passes a stricter wrong rule just as well, and an off-by-one at the bound.

**Why:** f0125 design reviews 001 F3 and 002 F1: `ghostTuning` was bounded so that no ghost covers more than a tile a tick. The case refused base 96 with k = 1.1 and accepted untuned and k < 1 configs, so "refuse any k > 1" passed it, and so did `>=` for `>`.

**How to apply:** at one input, accept the largest allowed value (here k giving exactly 120) and refuse the next (121); add an accepted value only the stricter wrong rule would refuse (base 30, k = 2); list those wrong rules as mutants and run them.

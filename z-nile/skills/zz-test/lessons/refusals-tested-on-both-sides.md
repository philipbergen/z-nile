---
title: A refusal's spec sits on both sides of its bound
when: both
tags: [specs, validation, bounds, mutants]
check: For each refusal, does a case accept the largest value the rule allows, refuse the next one, and accept a value that only a simpler, stricter wrong rule would refuse; which stricter rule would also pass my cases? And does a case accept every other use the protocol makes of the same command (the author's own spend beside a reviewer's), which the refusal must leave alone?
---
A spec that only refuses a value far over a bound, and accepts values far under it, passes a stricter wrong rule just as well, and an off-by-one at the bound.

**Why:** f0125 design reviews 001 F3 and 002 F1: `ghostTuning` was bounded so that no ghost covers more than a tile a tick. The case refused base 96 with k = 1.1 and accepted untuned and k < 1 configs, so "refuse any k > 1" passed it, and so did `>=` for `>`.

**How to apply:** at one input, accept the largest allowed value (here k giving exactly 120) and refuse the next (121); add an accepted value only the stricter wrong rule would refuse (base 30, k = 2); list those wrong rules as mutants and run them.

c0263 design review 007 F4: an append-only rule's spec edits every cell of an old row, not one: a validator that skipped the detail cell let a direct push turn a stale approval current.

**Note (c0306's prep, 2026-11-14, design review 001 F1):** the accepted side includes the protocol's own other calls of the refused command. c0306 refused `spend --phase design-review` without `--model` and a `design-review-NNN` note in a marked item, which also refused the author's refute spend and answering span that z-design and z-raft record with the same phase. No case spent on a refute.

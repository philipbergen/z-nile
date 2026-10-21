---
title: A promoted spec never asserts a count of live tracker items
when: both
tags: [specs, regression, tracker]
check: Does any promoted case's threshold depend on how many items are unfinished, prepared or in flight, which change independently of the code?
---
A regression spec that reads the real tracker and asserts "at least N items" goes red when the backlog shrinks. That happens in some unrelated raft's `done` gate, which can't override a chore's promoted spec.

**Why:** R0043 code review 001 F1: c0114's `classified.spec` required at least 10 unfinished items with a `check` line. Today there are 20, and they drop to 9 once three in-flight rafts finish.

**How to apply:** prove the mechanism on a fixture, and let the live loop only require that every item it finds behaves (`listed == expected`), with no floor. If an empty live set must fail, say why in the design.

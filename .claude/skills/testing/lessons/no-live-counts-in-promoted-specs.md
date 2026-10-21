---
title: A promoted spec never asserts a count of live tracker items
when: both
tags: [specs, regression, tracker]
check: Does any promoted case's threshold depend on how many items are unfinished, prepared or in flight, which change independently of the code? And does any promoted case walk a live set of items (every `done/` folder, every unfinished item) whose members another raft's `done` adds or changes?
---
A regression spec that reads the real tracker and asserts "at least N items" goes red when the backlog shrinks. That happens in some unrelated raft's `done` gate, which can't override a chore's promoted spec.

**Why:** R0043 code review 001 F1: c0114's `classified.spec` required at least 10 unfinished items with a `check` line. Today there are 20, and they drop to 9 once three in-flight rafts finish.

**How to apply:** prove the mechanism on a fixture, and let the live loop only require that every item it finds behaves (`listed == expected`), with no floor. If an empty live set must fail, say why in the design.

The same holds for any promoted spec that reads the live tracker: it must stay green whenever another raft finishes. Ask which later `done` changes the set it walks. R0043 design review 006 F1: c0114's `finished.spec` required every `done/` check.sh to be rewritten, so the next raft to finish, c0114 itself included, would have moved an unrewritten one in and failed its own gate. The fix walks a fixed list (the files finished when c0114 lands) and proves on a fixture that a later finish leaves it green.

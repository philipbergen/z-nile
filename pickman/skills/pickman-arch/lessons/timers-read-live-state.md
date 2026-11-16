---
title: A timer that folds input state reads it when it fires, by identity, and judges no clock
when: both
tags: [input, adapters, timers]
check: When an adapter schedules a callback that folds input state (a held-still tap timer), does the callback read the live state and find its subject by an id that is never reused, rather than a copy taken when it was scheduled? Is there a case where the timer fires after its subject is gone (lifted, focus lost, re-layout), asserting nothing happens and the next input still works? And if the callback compares a clock to decide, what happens when it fires a hair early? And when the stale timer fires in those cases, is another candidate it could wrongly act on present (a second finger down, a new finger after a focus loss or a re-layout), so that a wrong or reused id fails?
---
A closure over the state at scheduling time replays a finger that has since lifted, so a tap turns into a late look and the control stays taken. A one-shot timer that re-checks `os.clock()` against the press time can fire a moment early, decide "not yet", and never run again.

**Why:** d0149 design review 003 F1, F3: a mutant that ticked the press-time fingers passed every adapters case (all fired the timer while the finger was still held); the timer compared `os.clock()` with the press time, and float rounding alone left 10 in 100,000 sums short.

**How to apply:** the fold takes the event's id (`Touch.hold(state, id, ctx)`) and acts only if that finger is still there and undecided; the timer itself is the witness that the time passed; spec cases fire the timer after a lift, a focus loss and a re-layout, and early, each followed by a working input.

d0149 design review 004 F1: a timer that promoted the newest finger, and ids reused after focus loss, both passed every case, because each stale timer fired before any second finger was down; a double tap would have swung the view on the second tap.

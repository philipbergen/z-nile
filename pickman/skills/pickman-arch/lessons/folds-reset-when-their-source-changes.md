---
title: A fold over a device's readings resets when its source changes
when: both
tags: [input, adapters, state]
check: When the reading source of a stateful input fold changes (a disconnect, another controller takes over, a window loses focus), is the fold's held state reset, and is there a case for each change?
---
An adapter that folds a device's readings into events (a stick into one turn a push) keeps state between readings. When the readings start coming from somewhere else, that state belongs to the old source: kept, it makes the new source's first push look like a held one, and the event is lost.

**Why:** R0058 code review 001 F3: Sticks kept the left stick's engaged sector across a disconnect and across a change of driving controller, so the next controller's first push the same way sent no turn (a missed junction). A reset on a nil read alone would not have covered two connected pads, where the reading never goes nil.

**How to apply:** have the reader say which source a reading came from, reset the fold on a nil read and on every change of source, and give each change a stub case (disconnect then the other source, two sources handing over, the same source reconnecting at rest).

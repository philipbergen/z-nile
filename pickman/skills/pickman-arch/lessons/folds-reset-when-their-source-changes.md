---
title: A fold over a device's readings resets when its source changes
when: both
tags: [input, adapters, state]
check: When the reading source of a stateful input fold changes identity (another controller takes over, a window loses focus), is the fold's held state reset, is a failed read left alone (not a change of source), and which case fails if each reset is removed?
---
An adapter that folds a device's readings into events (a stick into one turn a push) keeps state between readings. When the readings start coming from somewhere else, that state belongs to the old source: kept, it makes the new source's first push look like a held one, and the event is lost.

**Why:** R0058 code review 001 F3: Sticks kept the left stick's engaged sector across a disconnect and across a change of driving controller, so the next controller's first push the same way sent no turn (a missed junction). A reset on a nil read alone would not have covered two connected pads, where the reading never goes nil.

**How to apply:** have the reader say which source a reading came from and reset the fold only when that source changes identity, with a stub case for each change (another source after a dropout, two sources handing over).

**Note** (R0058 code review 002 F1): a failed read is not a change of source. Round 001's fix also reset the fold on a nil read; no case needed it (the next source differs anyway), and on the one path it alone decided, the same pad dropping mid-push and coming back still held, it sent a second turn the player never made. Keep the fold across a nil read, and give every reset a case that fails without it, plus one for the same source coming back mid-hold.

---
title: A guard on an engine side effect follows the engine's inputs and outlives the read
when: both
tags: [adapters, input, frames]
check: For each flag that suppresses an engine value (a mouse delta, a default control), does it count what the engine counts (every physical input, not the ones your model kept), and what does the reader see when the set and the clear happen in the same frame, before it runs?
---
An adapter that suppresses something the engine does on its own (a touch moving the locked mouse) has to guard every input the engine reacts to, for as long as the engine's value can still carry it. A guard computed from the pure model's filtered state misses inputs the model ignored. A flag cleared by an input event races the render step that reads the suppressed value: both happen in one frame, and the clear wins.

**Why:** R0012 code review 001. F1: `onTouch(false)` cleared `mouseHeld` from `InputEnded` before the camera's render step read `GetMouseDelta`, so every fast swipe ended with a yaw jolt. F2: the held state followed the fold's tracked fingers, so an ignored second finger moved the mouse once the first lifted.

**How to apply:** count the adapter's own record of physical inputs, not the model's. Make every change of the guard also set a latch that the reader clears after it reads, so the frame of the change is skipped.

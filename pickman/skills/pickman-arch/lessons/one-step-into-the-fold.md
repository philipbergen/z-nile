---
title: Every path into an input fold goes through the event handler's one step
when: both
tags: [input, adapters, timers, state]
check: Does every path into the fold (a touch event, a timer, a hook) go through one shared step that applies the source-change reset before it reads the fold's state, rather than a hand-made copy of the handler? Is there a case where the source changes with no event before the second path runs?
---
A second path written by hand beside the event handler gets the order wrong: Luau evaluates `fold(state, controlsNow())` by reading `state` before `controlsNow()` resets it, so the reset is written over.

**Why:** d0149 design review 005 F1: the look circle's hold timer called `Touch.hold(fingers, id, controlsNow())`; after a re-layout with no touch in between, the timer folded the old fingers against the moved circle and brought back a let-go thumb, turning the view a quarter. Every case sent a touch before the timer, so none saw it.

**How to apply:** one local `step(fold)` in the adapter reads the source (and resets), then folds, applies the effects and reports; every path calls it; a case changes the source with no event before the other path fires; the hand-made copy is a mutant row.

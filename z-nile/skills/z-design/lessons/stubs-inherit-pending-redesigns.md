---
title: A stub that drives an input path inherits that path's pending redesigns
when: design
tags: [stubs, input, execution-window]
check: Which in-flight issues change the events this sequestered stub fires, and does the design name each with its order and a fallback for the stub?
---
A sequestered spec that runs an adapter on a stub fires particular engine events (touch events on `UserInputService`, a stick poll). An in-flight issue that moves the adapter to other events leaves the stub firing nothing the adapter hears, and the sequestered case fails on correct code in a file the executor may not edit.

**Why:** f0143 design review 002 F4: controls.spec's swipe case drove `UserInputService.InputBegan`, `InputChanged` and `InputEnded`, while d0151 (touch on a phone) is to be fixed "at the cause", possibly on other events, and d0149 replaces swipes with a circle; neither was named, and d0149 wasn't ordered against f0143.

**How to apply:** list every in-flight issue that may change the path the stub drives, order each against this issue, and record the fallback: an experiment with a pass/fail question, and a chore that re-points the stub before z-ready if the path moves.

---
title: A constant copied from one game is a per-game parameter
when: design
tags: [copy, parameters, per-game]
check: For each constant the copied feature keeps, is its unit or its value one game's (a window in that game's ticks, a step rate, an event's timing), and if so, is it a parameter each game's adapter passes, with the copied value documented as that game's?
---
A library feature copied from a game keeps that game's tuning in its constants. Where a constant's unit or value belongs to one game (a window counted in that game's steps, a pause in its ticks, an event it emits at a moment its own rules choose), the library takes it as a parameter, and the copied value stays only as that game's documented default for its adapter (arcade-arch rule 2: per-game differences are parameters). State, too, the contract the copied logic assumes about each game's events (when the run's end is announced, what the event carries).

**Why:** f0197 design review 001 F4: the copied `Hiscores.leave` kept pickman's 45-step window (its 1.5 s dying pause at 30 steps a second) as a constant for every title, though Snake steps at its own rate and holds a 10 s revive offer; and the contract that GameOver is the run's end after any revive offer, carrying the final revives, was unstated.

**How to apply:** walk the copied module's constants and ask, for each, whose unit it is in. Make the per-game ones arguments (`leave(steps, sawOver, window)`), keep the old value as the old game's named constant, and add a case that a different window is honoured.

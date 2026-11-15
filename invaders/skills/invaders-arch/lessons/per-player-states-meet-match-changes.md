---
title: Two solo runs in one match meet match-level changes solo never allowed
when: design
tags: [two-players, pauses, events, simultaneous]
check: For each per-player state a solo run has (dying, game over, waiting on a revive), can a match-level change the other player causes (the wave's clear, the wave's start, the match's end) arrive while one player is in it, and does the design name the rule (does the state's timer count, what ends it) and the event that marks its end for each such pair, with a case?
---
In solo, a dying pause stops the whole game, so nothing else can happen during it. Put two solo runs in one match and the other player can clear the wave while one is dying. The pause's timer, its end and its `Respawn` event are then undefined, and the view has no event to draw the return from.

**Why:** f0217 design review 001 F2: a player dying when the other cleared the wave stayed `dying` through the wave pause and came back at the wave's start with no `Respawn`.

**How to apply:** list each player state against each match transition. For every pair that solo never allowed, write the rule (counts or freezes, what ends it, which event, where in the tick's order), and add a case and a mutant.

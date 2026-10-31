---
title: A control that tells a tap from a pull acts on neither until it has decided
when: both
tags: [input, touch, gestures]
check: When one control has two gestures told apart by time or distance (a tap and a pull, a press and a hold), does any effect of one gesture fire before the fold has decided which it is, and is there a case that taps the control off its exact centre, held still, and asserts the tap's effect is the only one? Where the decision can come with no input event (a thumb held still), what gives the fold the time?
---
A fold that starts the pull's effect on the press and later decides "that was a tap" has already done the pull: a look that swings and springs back, a turn already sent. Specs that tap the control's exact centre never see it, because a pull from the centre is no pull.

**Why:** d0149 design review 001 F2: the look circle pointed the view on the finger going down, so a tap at 0.6 of the radius turned the view a quarter (or behind, below the centre) and back before it hopped; every spec tapped the centre. The fix holds the look until the finger has moved the tap's slop or been held the tap's time, which needs a per-frame tick for a thumb that rests without moving.

**How to apply:** give the fold a "decided" state per finger; emit nothing of the slower gesture before it is set; feed time through a tick the adapter calls every frame; test taps off the centre with a small wobble, and a still finger past the time limit.

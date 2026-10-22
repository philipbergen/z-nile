---
title: An age check uses the last tick that was in play
when: both
tags: [specs, time]
check: When an age check means the last step that was in play and it runs both at the end of a step and at the start of the next, does each call see that step's tick, and is there a spec where the next step has already incremented the clock?
---
A clock that increments at the top of a step has already moved by the time a start-of-step check runs. Passing that new tick into a comparison written for the step that just finished treats a pause step as one more step of play.

**Why:** R0035 design review 007 F1: `forgetYoungHop` used `s.tick < hopped + 2` at both sites. After the step following take-off, `Session.kill` (between steps) advanced the clock to `hopped + 2` before the check, so the death pause played the arc over the walls. Every in-step death still cleared, and a kill immediately after take-off still cleared, so the specs stayed green.

**How to apply:** name the tick each call sees. On a step that begins in play, it is this step. On a step that begins already paused, it is the previous tick. Spec both sides of the boundary (the last tick that must be forgotten, and the first tick that must be kept), including a pause that starts between steps.

---
title: A new phase before the game over meets every rule that assumes the run ends in the dying pause
when: design
tags: [session, hiscores, leaving]
check: What happens to the run's submission when the player leaves (or the server closes) in the new phase, held or not, and does a case run it through Sessions and Submits?
---
A departed player's run is kept only `Hiscores.LEAVE_STEPS` (45) steps, sized for the classic dying pause, and `Submits` hears step events only. A phase that sits between the last life and the game over (an offer, a held offer) can outlast that window, so a player who leaves in it is dropped with no submission.

**Why:** f0145 design review 001 F1: the continue offer (150 steps, or held while a purchase screen is open) came after the last dying pause; a player who left in it lost their hiscore, and every spec passed because none ran a departure through the real Sessions and Submits.

**How to apply:** list every rule keyed to the run's end (LEAVE_STEPS, server close, Submits' step-only hearing) against the new phase, end the phase on leaving (here `Session.leave` on `PlayerRemoving`, before parking), and add cases that leave in each part of the phase through the real adapters.

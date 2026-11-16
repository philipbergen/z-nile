---
title: A user's step comes before the experiment that needs it
when: design
tags: [experiments, user, beta]
check: Does any experiment or outcome need something only the user can do (create a Roblox place, set a secret, publish), and is that step placed before it (the experiments phase asks for it first), not in Observed, which the human does after the work?
---
Observed steps are the human's, after the raft's work. An experiment that needs a user's step (a place created on Roblox, a place id set) can't run if that step is only listed there.

**Why:** c0190 design review 006 F2: I3's E5 (a party teleport on Beta) needed the Invaders place on Beta, which the design created only through I3's own Observed step.

**How to apply:** for each such step, name where it happens: in the experiments phase, as the first request to the user, before the experiment that needs it.

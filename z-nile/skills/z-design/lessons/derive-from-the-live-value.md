---
title: A number defined by another feature's behaviour reads that feature's live state
when: design
tags: [tuning, coordination, derivation]
check: Where the user defined a number by another feature's behaviour ("as long as a ghost takes to walk 10 tiles"), does the design read that feature's live, configured value (the member's own set, the session's config), and does any prep in flight change that behaviour through config rather than the default table?
---
A tuning prep changes the live value (a config factor, a per-member field) without touching the default table, so a derivation from the table silently stops matching the behaviour the user named.

**Why:** f0126 design review 009 F2: the pick was timed from `Levels.ghostSpeed` untuned, while f0125's prep slows the shipped ghosts by `ghostTuning = 1/1.1`; the shipped pick would have been 43 steps where a hunting ghost takes 47 to walk ten tiles, and every spec ran the default config.

**How to apply:** read the value from the same live state the other feature uses (here `member.ghosts.tuning`), and add a case that sets that state to a non-default value.

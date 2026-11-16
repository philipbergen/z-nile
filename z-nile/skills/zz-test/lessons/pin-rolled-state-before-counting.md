---
title: Pin rolled state before counting on it
when: both
tags: [fixtures, seeds]
check: Does any assertion compare against a value built up by earlier seeded rolls the case did not fix (a banked count, held shots, a flag a boon may set), and does the case set that value itself just before the step it measures, so another seed or another issue's draw order cannot turn it red?
---
A case that plays several seeded rounds before the step it tests inherits whatever those rounds rolled. Its expectation then holds only for the seed and the draw order it was written on.

**Why:** f0147 design review 001 F2: the bonanza case expected `picks.fast == fast + 1` after the tenth pick, reading `fast` after nine rolled boons; when one of them banked a faster pick, the tenth pick spent it and the count stayed level. Seed 1 passed; seeds 6, 13 and 20 failed on the unchanged prototype, and f0126 (not yet landed) owned the draw order.

**How to apply:** set the state the assertion reads (here `picks.fast = 0`, `longHops = false`, `shots = 0`) right before the measured step, and add a sub-case for the other starting value when the rule depends on it (one banked: one spent, one granted). Run the case on a handful of seeds once to see that it does not depend on them.

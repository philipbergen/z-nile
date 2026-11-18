---
title: The item that lands second does the wiring its design hands to "whichever lands second"
when: build
tags: [handshake, deviations, dispatch]
check: Does the Verification log answer every "whichever lands second" (or "the second lander") line of the Design: done in this layer, or not done, with why and who now holds it?
---
A design that overlaps an item in flight often settles the overlap as "whichever of the two lands second wires the other's text". By execution one of them has landed, so the line is an instruction to this layer or to nobody; a Verification log that lists deviations and skips it drops the wiring silently.

**Why:** R0068 review-001 F5 (c0136): the design gave the dispatcher's reviewer prompt (`./zn lessons --check-review`) to whichever of c0136 and c0117 landed second. c0117 was done, so it was c0136's; the prompt was not changed and the log did not say so.

**How to apply:** before finish, search the issue document for "lands second", "second lander" and "whichever"; for each, check whether the other item is done, and do the wiring with a spec case, or log why not and to whom it goes.

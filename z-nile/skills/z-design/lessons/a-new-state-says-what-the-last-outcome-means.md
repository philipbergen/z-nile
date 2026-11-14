---
title: A new state says what the last outcome means
when: design
tags: [dispatch, lifecycle, states]
check: When the design adds a state an item can leave (blocked, resolved), does it say what each reader of the item's last recorded outcome (the dispatcher's last step, a run's exit, a cached verdict) does after the item leaves that state, and through every way the chain resumes it, not only `retry`?
---
A chain that remembers the last step's outcome reads it again after the item moves on. "retry reruns the step" said nothing about a plain resume, which still saw the old ok outcome and stopped with "z-design ended but … still new".

**Why:** c0250's prototype (prep, 2026-11-13): after `resolve`, `./zn dispatch <id>` stopped on the old outcome until the copy of the resolution also cleared it, as `retry` does. The open-list fallback stop also fired again until it dropped the ids the resolution ruled.

**How to apply:** list every stored fact a step leaves (its outcome, its open list, its exchange), and for each way the item re-enters the chain say whether the fact is cleared, kept or replaced, with a case for each.

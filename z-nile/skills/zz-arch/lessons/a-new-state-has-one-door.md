---
title: A new state has one door
when: build
tags: [guards, publish, validators]
check: Which result state does this new strict validator protect, and can any other accepting branch of the same guard (an older, looser one) produce that state, or part of it, without the validator?
---
Adding a strict validator for a new edit shape protects nothing if an older branch of the same guard already accepts part of that shape. The new branch says "only exactly this", while the old one says "anything that changes only this line", and the old one runs first.

**Why:** R0115 review 001 F1: c0278 added `closing.guard`, which accepts a document edit only when it is exactly one close (`status: closed-…` plus `wont_do:`). The publish guard's older status-only test (`withoutStatus` equal on both sides) still accepted `status: closed-…` alone, before the new guard was consulted, and `validateMoves` let a move stamp its new document closed. Either path published a closed issue with no reason.

**How to apply:** route on the result state, not on the edit shape: when the new content is in the protected state (here `closing.closedDoc`), the strict validator is the only way in, and every other branch refuses it. Keep the decision a pure function over (before, after) and add a spec case for each older branch trying a partial form of the new state.

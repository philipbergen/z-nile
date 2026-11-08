---
title: A rule keyed on "the claim this checkout remembers" lists every claim path and whether it writes that memory
when: design
tags: [claims, memory, refusals]
check: For each command that publishes a claim stamp, does it update this checkout's memory of the claim, and what does the rule answer when the checkout remembers nothing?
---
A refusal that compares origin's stamp with a per-checkout memory breaks every flow whose claim path never wrote the memory, including the checkout's own re-claim.

**Why:** f0265 design review 003 F1: `status <R-id> preparing` never wrote the memory, so the new refusal would have turned c0053/commands-prep red and refused the taker of a rafting takeover.

**How to apply:** list the claim commands, make each write the memory, say that no memory passes, and run the suite on the rule before naming Overrides.

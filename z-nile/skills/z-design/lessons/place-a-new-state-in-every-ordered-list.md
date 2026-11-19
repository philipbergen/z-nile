---
title: Place a new state in every ordered list
when: design
tags: [design, ordering, rules]
check: For each new kind of state the design creates, which line of each ordering, refusal list and reason list takes it, and does that list's header still hold for it?
---
A design that adds a state late (in a later section, or after a review round) has to go back to every list it already wrote and say where the new state falls. A list written before the state existed takes it by accident, under whatever line happens to match.

**Why:** R0129 final review 001 F2 (f0399, 2026-11-17). The work picks were written as two tiers, "nothing unmet" first. Section 6 then added a raft built on a raft that has not landed. Tier 1's line "an active raft this author holds" matched it, so the worker resumed a raft with something unmet ahead of tickets with nothing unmet, against "the tier always wins". The design review did not catch it either.

**How to apply:** after the last section is written, list the states the design added and walk each ordered list, refusal list and reason list with them. Add the line or the exclusion, and a spec case that puts the new state beside an item of the earlier tier.

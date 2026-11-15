---
title: Per-player state the library keys by title is pinned with two titles for one player
when: design
tags: [library, adapters, caches, specs]
check: When a library adapter keeps per-player state (a cache, an in-flight flag, a bound, a once-per-join answer) that is also keyed by a title or a board, does the Design say so in those words, and does a case drive two titles for one player and assert that neither's read, write, bound or answer touches the other's?
---
A library feature serves every title from one server, so its per-player state is per player and title. A spec that only ever names one title cannot tell that apart from state kept per player alone, and the portal, which asks for four titles at once, then gets one title's record for all four.

**Why:** f0201 design review 001 F2: Wallet's slots were per (player, title) in the prototype, but the Design said "per Player object" and every read, use and refund case named Pickman; a Wallet keyed by player alone passed all 88 cases, and in it the portal's Snake card would show Pickman's record and three of four card reads would answer "busy".

**How to apply:** write "per player and title" in the Design; add cases that read two titles within the cache span (each its own record, two store reads), hold one title's read while the other's goes through, and use one title's bounded call without starting the other's bound; add the mutant "one slot per player".

---
title: A read a client can trigger is guarded in flight and after a leave
when: design
tags: [server, budgets, concurrency, remotes]
check: For each per-player read or cache a client request can start, what happens when the same client asks again, or leaves, while that read is yielding, what happens to requests right after a read that failed (is the failure held for a span, or does every request read again), and what does a call made after the player left do? Does a spec model a yielding store?
---
A server read that a client remote can trigger spends a server-wide budget. If its cache entry is written only after the read returns, every request that arrives during the yield starts another read, so one client firing the remote can exhaust the budget for every player. A read that returns after the player left writes an entry that outlives them.

**Why:** R0044 design review 1 (F2): the lobby's "your best" read was cached per player for CACHE_TTL, but the entry was set after `GetAsync`, so five requests during one read made five reads; a read that finished after `PlayerRemoving` left a stale best that a quick rejoin was shown. Synchronous stubs showed neither.

**How to apply:** store an in-flight marker before the yield, skip the read while it is there, and store the result only if the marker is still that read's and the player is still present. Give the spec stub a store call that yields until released, and cover a burst during the read and a leave during the read, each with a mutant.

**Also:** f0201 design review 001 F8: only a successful read was cached, so while the store failed fast every request read again and one client kept the shared budget throttled; a failed read holds its answer for a retry span with no store call. F10: a call made after the player already left (a place that yields first) still spent their free start and made a slot nothing dropped; such calls answer without a store call or a slot, except a give-back owed to them.

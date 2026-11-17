---
title: A shared library handle's wiring methods are safe to call twice
when: both
tags: [library, adapters, handles, remotes]
check: For each method of a memoized library handle (one per key, shared by every caller in a place) that connects to an event or a remote, what happens when a second caller calls it with the same argument and with a different one, and does a case pin both?
---
A library adapter that hands every caller in a place one handle per key (`Boards.open(prefix)`) invites a second caller. Its per-request state (waiters, in-flight reads, caches) belongs to the handle, so a wiring method that connects a handler each time it is called answers twice on the same channel, or answers the waiters of one channel on another's.

**Why:** R0121 code review 001 F2: `serve(remote)` kept each board's waiters on the handle but replied on the remote of whichever call ran the read, so a second `serve` on the same remote answered every request twice and one on another remote lost answers, with every spec green because each spec served once.

**How to apply:** make the wiring method do nothing when called again with the same argument and raise when called with another (or key the per-request state by the argument), say so in its comment, and add a unit case for each: one request after two `serve(r)` calls is one answer, and `serve(r2)` after `serve(r)` errors.

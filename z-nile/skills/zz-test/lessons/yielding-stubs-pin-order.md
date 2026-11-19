---
title: Pin an order around a yielding call with a stub that yields
when: both
tags: [stubs, ordering, mutants]
check: Does any spec that pins "X happens before Y", where X may yield in the engine (a store write, a remote call), use a stub for X that actually yields until the spec resumes it, and does it kill `task.spawn` and `task.defer` mutants of that call?
---
A stub that returns at once cannot tell a direct call from one handed to `task.spawn` or `task.defer` (the fake engine runs both at once), so the order it claims to pin is unpinned.

**Why:** f0148 design review 003 F1: Starts' store hook could be spawned or deferred and lobby.spec stayed green, while in Roblox the teleport would go before the choice was written (START LEVEL 3, then level 1).

**How to apply:** make the stub record `coroutine.running()` and yield; assert nothing that should wait has happened yet, then resume it and assert the rest; add the spawn and defer mutants to the Rules table.

**Also:** R0110 code review 001 F1: f0201's stub store yielded, but its held `GetAsync` read the value when released, so a read held across a grant always answered the newer record and no case could show a stale cache. A held read answers the value the store held when the request was served (read it before the yield), and a held write can be held after it was applied, so a spec can return answers out of the order the store applied them.

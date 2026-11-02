---
title: Pin an order around a yielding call with a stub that yields
when: both
tags: [stubs, ordering, mutants]
check: Does any spec that pins "X happens before Y", where X may yield in the engine (a store write, a remote call), use a stub for X that actually yields until the spec resumes it, and does it kill `task.spawn` and `task.defer` mutants of that call?
---
A stub that returns at once cannot tell a direct call from one handed to `task.spawn` or `task.defer` (the fake engine runs both at once), so the order it claims to pin is unpinned.

**Why:** f0148 design review 003 F1: Starts' store hook could be spawned or deferred and lobby.spec stayed green, while in Roblox the teleport would go before the choice was written (START LEVEL 3, then level 1).

**How to apply:** make the stub record `coroutine.running()` and yield; assert nothing that should wait has happened yet, then resume it and assert the rest; add the spawn and defer mutants to the Rules table.

---
title: An adapter that listens to every step reads the events before it touches the engine
when: both
tags: [adapter, performance, datastore]
check: For each function an adapter hands to a per-step listener (`Sessions.listen`, a frame handler), what does it call on the engine when the step holds nothing for it, and is that nothing?
---
A listener of every step runs 15 times a second for every session. Anything it does before it has looked at the step's events is paid on every one of them, and where that call fails (a store that cannot be opened, a service that is missing in Studio) it fails 15 times a second.

**Why:** R0094 code review 001 F2 (f0148, 2026-11-16). The game place's `Bests.reached` opened the DataStore first and then looked for a `Ready` with reason `level`. Where the place cannot reach DataStores, every step of every session retried `GetDataStore`. The sequestered adapters spec could not see it: its cases reach the store only through a level event. Caching the failure would have been the wrong fix, since a transient failure would then stop the best from ever rising on that server.

**How to apply:** scan the events first and ask the engine only inside the branch that has work. Pin it in a place-tier case on a stub that counts the engine call: many steps with nothing for the adapter make zero calls, one step with the event makes one (`tests/place/bests-open.spec.luau`).

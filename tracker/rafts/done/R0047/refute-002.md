# R0047 refute 002

- F1: fixed 92d8c10f: `writeWhole(path, text, me)` takes the caller's pid for its temp name, so nothing runs `sh` between a claim and its record; every caller passes `me` (the top and the waiter read it once before waiting, a guarded worker reads it once in `fence.enter`). consequences: none beyond the signature (a local function, three callers); c0127's specs, `lock-start-ids.spec` and c0058's lock.spec 30/30.
- F2: fixed 92d8c10f: `tests/tooling/lock-start-ids.spec.luau`'s fixture commits as `lock-start-ids@example.invalid`, as refute-001 said. consequences: none (the identity scan accepts any `@example.invalid`).

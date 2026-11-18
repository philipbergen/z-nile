---
title: A spec that runs a real boot in a coroutine loads its modules first, on the spec's own thread
when: build
tags: [specs, adapters, coroutines, lune, boot]
check: Does this spec run a real Main (or any source that requires modules) inside a coroutine it resumes itself? If so, are those modules, and the Logic they require, loaded on the spec's own thread first, so that the boot's requires only hit a cache? Does the case assert the boot thread finished, not only that it raised nothing?
---
A Lune `require` may yield. Inside a coroutine the spec resumes by hand, that yield suspends the boot with no error, so the Main stops at its first require. Its later adapters never start, and every case fails far from the cause (no binding, no screen). Asserting that the boot raised nothing passes.

**Why:** R0117's rafting (2026-11-15). A raft-level spec ran the portal's client Main in a coroutine, with CarouselView and PlayButtons loaded on demand. The first `require` of `@logic/Card` inside CarouselView yielded, `start` never bound its keys, and all four cases failed on a missing binding. Loading every ModuleScript of the client folder on the spec's thread before resuming the boot fixed it.

**How to apply:** before resuming a boot thread, load each module it will require through the same `env.require`, on the spec's own thread. Then assert `coroutine.status(boot) == "dead"` after the resume, as f0205's client spec does with `booted`.

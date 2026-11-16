---
title: A retry or a lease is pinned by counting attempts, not by the end state
when: both
tags: [specs, mutants, retries, leases]
check: For each rule "if the push is rejected, re-read and repeat", does a case count the attempts (a shim that logs each push), since the end state of a rejected-then-retried write equals that of a write with no lease and no retry?
---
A race that the lease rejects once and the retry then wins leaves the same refs as an unprotected write that never raced. A case that reads only the end state passes for the mutants "no lease" and "no retry" masked by luck.

**Why:** c0274 prep, the atomic swap of heartbeat branches: the first case read the final branches and survived the no-lease mutant; counting the shim's atomic pushes (two) killed it and the no-retry and non-atomic mutants.

**How to apply:** have the git shim log every call of the write, arm the race once, and assert the number of attempts as well as the result.

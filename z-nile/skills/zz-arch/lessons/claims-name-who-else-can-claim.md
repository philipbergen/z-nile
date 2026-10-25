---
title: A claim that stops stamping an item names who else can claim it
when: design
tags: [concurrency, claims, state]
check: For each item this claim no longer stamps, which other command can claim it while the claim is open, and what refuses or conflicts when the two meet?
---
Narrowing a claim (stamping a raft but no longer its members) frees the unstamped items for every other claimant. Unless the design names each command that can claim them in the window and the point where the two meet (a refusal, a conflicting line), the second claim is silently overwritten when the first lands.

**Why:** c0116 design review 001 F1: the raft-only stamp left a prepared member open to z-design's `status <id> preparing`; the rafting worktree merged that status line cleanly, the carried move accepted any `preparing` stamp and restamped it, and `ready` then handed the issue out under a live design claim.

**How to apply:** list the items the claim used to cover and every command that can stamp them (design, rafting, ready, stop, release, recombine). For each, say which check refuses it or which line conflicts, in both orders (before and after the claim's own carried step), and give the case a spec. A carried step accepts another holder's stamp only when it is provably the same claim (the same stamp, or one this checkout made).

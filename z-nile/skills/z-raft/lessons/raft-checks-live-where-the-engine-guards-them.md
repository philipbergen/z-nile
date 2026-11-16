---
title: A raft check's spec lives where the engine sequesters and promotes it, or it is not written
when: design
tags: [raft, rc, sequestration, promotion, audit]
check: Before a raft check runs a spec file of its own, which `isSequesteredRel` rule and which review diff pattern cover that path, and what do `./zn done` and `./zn audit` do with it once the raft is in done/?
---
A raft's own folder is not a member's. The engine sequesters only an item's `check.sh` and its `acceptance/` files, `done` promotes only members' `acceptance/`, and audit reports a done item whose `acceptance/` is not empty as `spec-not-promoted`. A spec in any other raft folder (`checks/`) can be edited during execution without any guard noticing. Nothing runs it after `done`. Calling it sequestered in a header does not make it so.

**Why:** R0117 design review 001 F1. The first draft's RC2 ran `checks/play-keys.spec.luau`, which proved the joint between f0205's carousel keys and f0208's PLAY through the real client boot. It was labelled sequestered, but nothing sequestered it. Moving it to `acceptance/` would have broken audit after `done`.

**How to apply:** put a joint's proof in the member whose design owns it (the interface that assigns it), through z-design. Otherwise, wait for a tooling chore that makes raft specs first-class. A raft check stays a command over the tree (the map, the stack) that needs no spec file of its own.

---
title: A fixture drops its origin only when no command it runs needs one
when: design
tags: [fixture, origin, specs]
check: For each command a sequestered spec drives, does it call publishing(), raftingStart or refuseInMainCheckout, and does the fixture have the origin, worktrees and landing step that path needs?
---
A spec built on a clone with its remote removed cannot reach any path that publishes: `status`, `unfold`, `fold` and `recombine` refuse without an origin, and `new raft` takes its offline branch, so the published stamps the design adds are never run.

**Why:** c0263 design review 001 F1: the stamps spec removed the origin and then drove `status` and `unfold`, which refuse without one; four of the five captured outcomes rested on a case that could never pass, and the executor cannot edit a sequestered spec.

**How to apply:** list the commands a spec runs, read each one's entry (`publishing()`, `raftingStart`, the main-checkout refusal), and build the fixture with trackerfix (bare origin, worktrees, a landing step) for the published paths; keep a no-origin clone only for the offline ones, and run the spec once before review to see it fail at the missing feature, not at a refusal.

---
title: Mutants run against the final spec
when: design
tags: [mutants, specs, worktrees]
check: Was each mutant run against a copy of the final spec (after its last edit), and was the copy made after any `git checkout -f` or reset in the mutation worktree?
---
A mutation worktree is reset between mutants, and `git checkout -f` also resets a spec copied into it, so a mutant can silently run against the committed (older) spec. A spec edited after a mutant ran may no longer kill it.

**Why:** c0248's prototype: most layers-land mutants ran before the last edit to the spec, and one mutant (the raft document passed for the issue document's open list) survived until a case gained a ruling.

**How to apply:** copy the final spec into the mutation worktree after each reset, record the spec's hash with each mutant's result, and re-run any mutant whose spec changed after it ran.

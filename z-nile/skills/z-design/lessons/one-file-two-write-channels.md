---
title: A file written by published commits and by carried commits conflicts on every pair of appends
when: design
tags: [record, merge, conflicts]
check: Who writes this file, on which branch (a published commit on main, a commit a PR carries), and can two of them append between merges? What resolves it?
---
Two appends at the end of one file conflict in git even when they touch different lines. A record that is both published (a direct push to `main`) and carried by PRs (rafting, done, approve) conflicts the first time both happen between two merges, and numbered rows cannot be hand-merged.

**Why:** c0263 design review 003 F1: `new raft` committed a `rafted` row in the worktree, then `status <R> new` published an `unblocked` row into the same file; `mergeOrigin` aborted on the conflict. An experiment (E8) showed a union merge of the three blobs gives a valid file and a clean squash merge afterwards.

**How to apply:** give the rows no number, resolve a conflict confined to the record by union inside the engine's own merge helper, and build a published append from `origin/main`'s file; run the conflicting pair in a spec.

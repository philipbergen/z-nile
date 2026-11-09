---
title: In a layered raft, a layer's sequestered checks pin only what the upper layers keep
when: design
tags: [raft, layers, specs, sequestered]
check: For each case in an early member's spec of a raft, does it assert an absence or a permission that a later member's captured Problem changes, given that the raft's RC0 runs every member's check.sh on the final branch and a sequestered spec is not edited during execution?
---
A raft that lands as one PR runs every member's `check.sh` on the final tree (the raft template's RC0, and `./zn done`). A bottom layer's cases that hold only until a later layer lands turn red there, and an `Overrides:` line names promoted specs only, not the raft's own sequestered ones. The only way out is then to cut a later layer's captured scope.

**Why:** c0265 (core layer of the heartbeat raft) design review 019 F2: "a claim alone writes no beat" contradicted c0275's captured "claim paths beat", and seven beats made from a checkout that never made the claim contradicted c0274's rule that a checkout with no claim memory is refused.

**How to apply:** write the Design a "What the later layers keep" list, keep each early layer's cases to it, make every case act the way the final layer allows (a beat from the checkout that made the claim), and say in the Design that each layer's sequestered checks hold on the final raft tree. Run the earlier layers' specs on the later layers' prototypes.

**Note** (c0265 design reviews 019 to 021): reading the early layer's cases for absences is not enough. An absolute count of a shared resource (every branch on origin) is an absence assertion, and a command run in the worktree that made a claim is an effect the later layer adds. Prove the early layer on an **executable envelope**: a scratch patch of the later layers' captured effects in their plainest correct form, kept in `experiments/` and pinned by hash, and run all of the layer's spec files on the bare prototype and on the envelope. Its first run found three red cases the reading had missed. A pushed prototype carries no copy of the sequestered specs (`git ls-tree -r <proto> -- '*/tests/acceptance/<id>'` is empty).

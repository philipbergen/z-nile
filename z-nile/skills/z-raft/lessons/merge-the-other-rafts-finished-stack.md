---
title: Once the other raft of a cross-raft interface has finished its stack, merge its tip into this raft's prototype
when: design
tags: [raft, prototype, cross-raft, interfaces]
check: Has the other raft's finished tip been merged into this raft's prototype stack, and every member's check run there, or is the merge only predicted from documents?
---
An interface written from two documents is a prediction. When the other raft's stack is finished, a merge shows the real conflicts and the real register headroom, and says which raft's lead must adapt.

**Why:** R0099 design review 003 F3: R0100's finished tip changed the numbers and the conflict list (one `cmd.done` hunk, the board type blocks, two docs lines) that the raft had only predicted from R0100's draft.

**How to apply:** `git merge-tree` the finished tip into the prototype, record the conflicts and the measured headroom as an experiment, and say who runs the members' checks on the merged tree.

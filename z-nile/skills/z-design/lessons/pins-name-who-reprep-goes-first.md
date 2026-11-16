---
title: A chore that pins another item's file names, where its re-prep author reads it, who re-preps the chore if the re-prep goes first
when: design
tags: [reprep, ordering, sequestration]
check: If the target item is re-prepped between this prep and this item's `done`, can any edit the executor may make turn this item's checks green, and who has been told, in a document the re-prep's author reads (not only this issue's)?
---
**Why:** c0173 design review 003 F1 and c0174 design review 003 F2: both chores pin the exact text of items whose re-prep (promised by c0114 and c0120) is still owed. If the re-prep lands first, the blob pin and the exact-text checks fail by construction, nothing retires an issue but `./zn done`, and the chores' own documents are never read by the re-prep's author.

**How to apply:** write the ordering duty into the patched target documents themselves ("a re-prep started before cNNNN is done also re-preps cNNNN, its patches and pins rewritten, or makes it a member of the raft"), pin that sentence in the chore's check, and make the escalation signal explicit (the check's refusal message).

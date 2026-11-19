---
title: A regroup carries every earlier coherence finding that still applies
when: design
tags: [raft, regroup, coherence-review, fold]
check: For each finding of every earlier `design-review-NNN.md` in this raft's folder (and in retired rafts it absorbed) that named a member now back in the raft, is it in the Whole-raft design or the open list, or shown closed by that member's redesign?
---
When members that an earlier coherence review found in conflict are folded back into a raft, the new raft document re-reads that review's findings and carries each one that still holds, not only the ones the Whole-raft design's module walk happens to meet again.

**Why:** R0093 design review 002 F8 and F9: c0260, c0248, c0262 and c0250 were folded back unredesigned, and the rewritten document walked the shared modules, so two findings of review 001 that sit in a document shape (the capture record c0260 writes and c0262 reads) and a cut-over marker (`layers: reviewed`) were dropped.

**How to apply:** before writing the Whole-raft design of a regroup, list every finding of the earlier raft reviews that names a returning member, and for each write where it is answered now (an entry, an open bullet, or the redesign that closed it, with the member's grouped hash before and after).

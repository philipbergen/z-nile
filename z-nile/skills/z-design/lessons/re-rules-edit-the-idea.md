---
title: A re-ruling edits the Idea it changes
when: design
tags: [decisions, idea, consistency]
check: After the user re-rules a decision, does the item's `## Idea` (and every sibling the ruling names) say the new answer, not only a new Decided line beside an Idea that still says the old one?
---
A Decided line added beside an unchanged Idea leaves two answers in one document, and the designer who reads the Idea builds the old one.

**Why:** c0250's prep research: c0249's 2026-11-13 re-rule ("no person rafts, so z-raft does not ask for a rank") was added as a line, while its Idea still says "z-raft asks for a rank when it makes a raft".

**How to apply:** with the Decided line, edit the Idea's sentences the ruling changes, in the same commit, and grep the item for the old answer.

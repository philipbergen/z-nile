---
title: A branch never edits shared state main keeps writing; origin moves it when the branch lands
when: design
tags: [migration, shared-state, merges]
check: Does the branch change any file that main writes during the raft's execution (a counter, a map, a registry)? If so, what resolves the conflict at every merge of main, the PR's own merge after `done` included, and which copy does the branch's tooling read and write on origin meanwhile? And when another prepared raft changes the same mechanism, has its design been read for every writer and reader it adds, and do this raft's sequestered specs still pass once both have landed, whichever lands second?
---
A raft that moves shared state runs its own new tooling for its whole execution against an origin that still has the old layout, and main keeps writing the old copy all that time. If the branch edits that copy (moves it, empties it, replaces it with a marker), every merge of main conflicts on it. That includes the last merge, after `done`, where the skills allow only clean merges, so one capture landing during CI blocks the raft. A repair at each merge, and a check that the repair happened, only adds more steps that can go red between merges.

**Why:** R0043 design reviews 002 F1 and 003 F1 and F2. c0114 moved the id counter into `z-nile/`. First, its branch's engine looked for the new file on origin, which had only the old one. Then, with the engine fixed to read origin's copy, the branch's own move of the old file conflicted with every capture on main, and the audit check that a merge kept main's raises went red whenever main moved.

**How to apply:** leave the old copy byte for byte as main has it, and add no new copy on the branch. Let the tooling choose the live copy from the base it fetched, never the working tree: the old copy while origin has the old layout, and the new copy once origin has it. The first publish after the landing moves the state on origin, in its one lease push. It writes the new copy from the old one and leaves a marker that old tooling refuses, and a lost race retries on the new tip. Spec the three states: before the landing, the first publish after it, and every publish after that. Include a race against old tooling during the move.

**Note** (f0146 design review 001 F4): "whichever of two issues lands second adds it" names no owner and no check. Give a shared piece one owner, a `depends_on` that orders the two, and an acceptance case in the owner.

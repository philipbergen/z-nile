---
title: A record a later reader must attribute says which step wrote it
when: design
tags: [records, spend, readers]
check: For each record a new reader attributes to a step (a spend row, a stamp, a trailer), can two different steps write it with the same key in the same place, and if so, which field (a subject, a note, a phase) tells them apart, and does a case put both in one folder?
---
A reader that picks rows by phase, in the folder where they land, assumes each step writes its own kind of row there. A command that writes into another item's folder breaks that, with no error anywhere. A raft's spend writes into its members' folders, and two steps that share a phase then look the same.

**Why:** c0325 prep, round 2 (2026-11-15), experiment E1. `./zn spend <R-id> --phase prep` writes one row into each member's `spend.d`, none into the raft folder. A member's own design prep row has the same phase `prep` and the same subject. The design had the raft mode read the raft folder, which is always empty, and reading the members would have mixed the designers in. The fix gives the raft's row the subject `raft-prep` (`--note raft-prep`), and each mode reads only its own subject.

**How to apply:** run the real command in a fixture and look at where its record lands before designing the reader. Give each step a key no other step writes, and add a case with both steps' records in one folder.

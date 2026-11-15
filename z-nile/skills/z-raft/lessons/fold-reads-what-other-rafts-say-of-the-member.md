---
title: A fold reads what other raft documents say about the member
when: design
tags: [raft, fold, raft-plan, redesign]
check: Does any raft document (backlog, active or done) name this member with "Disagree", "redo" or "not the same PR", and has the member been redesigned since it said so?
---
`raft-plan` folds by type, project and size; it never reads the prose of other rafts. A member another raft has already judged incoherent with it, or one that must not share a PR with a given member, is folded back in as if nothing were known.

**Why:** in d0298's rafting, `raft-plan --apply` folded c0260 into R0092 beside c0264, although R0090's Whole-raft design says c0260 must be redone against c0261 (the idea review's activity name) and that c0264's AC8 (the README changes only in its two sections, judged against the merge base) holds only "if c0264's raft is not the same PR". The fold was unfolded before review.

**How to apply:** for every folded or newly grouped member, `grep -rn "<id>" */.tracker/rafts */.tracker/rafts/*/` and read each hit; a verdict that the member needs a redo, or must stay apart from a member here, means `./zn unfold <R-id> <id>` and the member goes back to z-design (z-raft never edits a member's design).

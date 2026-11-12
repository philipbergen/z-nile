---
title: Run every history-derived answer on the real tree's hard items before calling it proven
when: design
tags: [history, prototype, experiments]
check: Has each derived field been printed for a pre-compaction done item, a done item moved between roots, a PR landed by a merge commit, a raft id and an item with no published history, and does the design say what each prints?
---
A history reader proved on one tidy item passes its fixtures and gives false facts on the shapes the tree really holds.

**Why:** c0280 design review 001: E2 ran `who` on c0117 alone, which had none of these shapes; the reviewer's first other real ids showed the compaction commit as the idea, rafter, delivery and merge of 84 issues, a root move as the delivery of c0010, a branch's done commit as a merge, and an exit 1 on every raft.

**How to apply:** after the prototype passes its specs, print the answer for one real id of each kind (`./zn who <id>`), read each line against `git log`, and turn every wrong line into a fixture case and a mutant.

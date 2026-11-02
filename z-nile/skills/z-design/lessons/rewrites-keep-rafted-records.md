---
title: A command that rewrites other items' design files must keep rafted members' records
when: design
tags: [rafts, records, migration]
check: Does the rewrite touch any file raftplan.isDesignFile counts (a harvest.md counts), and does it run inside keepRecords like compact, remap and renumber?
---
A raft's `grouped:` line stores a hash of each member's design files. A command that rewrites one of them (a harvest ledger renamed by a lesson merge) makes `ready` and `fold` refuse the raft with no design change behind it, and the way out is an unfold, a fold and a new coherence review. Run such a rewrite inside `keepRecords`, so every entry that matched before is re-recorded, in the raft document and in its coherence reviews' `Grouped:` lines.

**Why:** c0181 design review 004 F1: `lesson-merge` rewrites the harvest.md of every item, and three backlog rafts carried records (R0053, R0054, R0062); one member's ledger alone names about thirty lessons.

**How to apply:** list the files a new rewrite changes, intersect with `raftplan.isDesignFile`, and add a spec case with a grouped raft whose member is rewritten.

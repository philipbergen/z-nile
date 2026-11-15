---
title: A record of what was reviewed covers every file it is made of, and mechanical rewriters re-record it
when: design
tags: [records, review, rewrites]
check: Which files make up the thing this record vouches for, and which commands rewrite them without changing what it means?
---
A hash that vouches for "the design this review read" is only as good as its coverage. If it covers one file of the thing, a change to another file passes unseen. And every command that rewrites those files for a mechanical reason (an id rename, a path move) changes the hash without changing the meaning, so it must re-record the hash or every later check refuses.

**Why:** c0116 design review 003 F1 and F4. The grouped record hashed only the issue's document, so a redesign of its `check.sh` or acceptance specs inside the rafting window reached `ready`. And `compact` and `renumber` rewrite ids in member documents, so every grouped raft would have been refused after a compaction.

**How to apply:** list the files the reviewed thing is made of once, as one function (c0116: `raftplan.isDesignFile`). Leave out files that change for other reasons (`spend.md`). Then grep for every command that rewrites those files (compact, remap, renumber, migrate) and make each re-record the entries that matched before its rewrite, and only those. Prove it by running that command on a tree holding a record, then the check.

**Note** (d0295 design review 001 F3): a migration that rewrites a reviewed document mechanically (moving cross-raft text out of a raft's Order) must keep what the review approved: the first rule rewrote the Order to the fallback order, which would restack a multi-member raft against its reviewed order. Ask: does the migration's output keep the meaning the review vouched for, and what does it do with the items where it cannot?

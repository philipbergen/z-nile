# Refute 012: R0042
Round 012 is this re-prep's round 7, run at the user's request to keep going until a review approves. It had no high finding.

Verification on `.worktree/proto-scope-fidelity`, synced with this tree:
- `scripts/check.sh --full` printed `GATE PASSED (full)`.
- c0111's `check.sh` passed 11/11, and c0119's passed 4/4.
- `promote-check R0042` printed `promote-check OK`.
- `luau-lsp analyze` of both acceptance folders and `scripts` exited 0.
- `lessons --check` printed `21 lessons, 104 harvest entries, ok`, and `--uncovered R0040 R0042` printed that every finding is covered.

- F1: fixed as recommended. Two rules change:
  - **A real compaction** is a commit whose map at that commit parses and differs from its parent's (`trail.sameMap`). A header edit, even one that also edits the item's document, is not one, so it is neither a life start nor crossed.
  - **An unproven change**, one that touched the document and left `tracker/compaction.txt` unreadable (a bad line, a deletion, a revert), starts a life. The walk stops there, and `trail.read` returns a note. `capture` then appends `(ambiguous: unproven compaction at <sha>)` and exits 0. With no add in that life, the capture falls back to its earliest commit.
  - `capture-cli.spec` adds the reviewer's two fixtures: a header edit together with an edit of a rotated item's document, and a broken map together with a document edit. `trail.spec` pins `sameMap` and the new fallback. The revert case goes through the same unproven path, since the revert leaves no readable map, and it stays reasoned.
  - On the real tree there is no change: one ambiguous (c0004), 98 first-add.
  - consequences: one more cached `git show` of the parent's map per cut. The mutants (any map change counts as a compaction, no marker, an unreadable map read as renaming nothing) were each killed. The tracker skill's capture row lists the third marker, and the spec pins it. When c0114 moves the map file, it has to pass the map's earlier path to the trail; c0111's Design says so.
- F2: fixed: the comment at the top of `trail.luau` now describes the rules as they are (lives, real compactions, unproven changes). consequences: none.

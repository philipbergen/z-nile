# Refute 003: c0118 (answers to design-review-003)
The prototype `proto-c0118` is amended. The prep folder's `prototype.patch`, specs and `c0118.md` follow it.

- F1: fixed with a new `history.spec` case, "both sides of a pair reset: an old id the counter hands out again starts undated". It runs as follows:
  - Done c0080 and active R0082 are renumbered away by the compaction (`c0080 c0081`, `R0082 R0083`); neither old id is on any pair's new side.
  - The counter then hands both ids out again: a new c0080 lands, and its `doneAt` is that later landing; a new R0082 is captured in the backlog, and its `activeAt` stays nil.
  - The compaction's own re-adds, c0081 in `done/` and R0083 in `active/`, stay undated.

  Mutants:
  - M66 (only the new side resets) is killed by this case.
  - M67 (only the old side resets) is killed by "a compaction's reuse of a done id…", so deleting either half fails a spec.

  §5 now says why both halves matter. Consequences: none beyond the fixture commits.
- F2: fixed: a compaction is now judged by the whole map it leaves. `parse` rebuilds each map's content from its hunks (the log has every commit that touched it, from its first add) and reads it with `ids.parseMap`. There is no second git call.
  - New case, "a pair the next compaction repeats word for word still counts": compaction B rewrites the map under a new header with the same pairs, and re-adds c0092 for another item in `done/`; c0092 stays undated.
  - Mutant M68 (judge by the diff) is killed.
  - The cache key is `v6`. The real tree's E1 is unchanged.
  - §5, AC2, Implementation step 2 and the lesson note are reworded.
  - Consequences: a map whose history the log doesn't start at its first add can't be rebuilt. The log is never truncated, and a shallow clone has no history at all, so this can't happen.
- Lesson: the reviewer's candidate ("a rule that resets both sides gets one case per side") is a note on `tracker/item-history-spans-moves-and-compaction`, harvested for F1.

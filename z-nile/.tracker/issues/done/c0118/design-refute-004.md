# Refute 004: c0118 (answers to design-review-004)
The prototype `proto-c0118` is amended. The prep folder's `prototype.patch`, specs and `c0118.md` follow it.

- F1: fixed by replacing the mechanism, as the review's alternative and the lead's direction asked. The diff-based forms of the renamed-id rule have now had holes in three rounds, so the map is no longer rebuilt.
  - The log line is `@@C %cI %H`. `history.parse(log, roots?, readMap?)` calls `readMap(sha, path)` only at a commit `isCut` flags, once for each map file that commit adds or changes. It passes the commit's own sha and the path the diff names there; the map has moved since, from `tracker/` to `z-nile/`.
  - `history.read` passes `git show <sha>:<path>`.
  - The whole map, through `ids.parseMap`, decides the renamed ids. A compaction writes the whole map with only its own pairs, so that one map suffices and no comparison with the parent is needed.
  - `applyMaps`, `contentOf` and the map state are deleted. With no reader, a missing map or a line that doesn't parse, every touched item is undated, with a warning.
  - The cache key is `v7`. E1 on the real tree is unchanged.

  New cases, with every earlier case still green:
  - "a pair a later compaction's map drops no longer renames…": compaction C maps only `c0950 c0951`, dropping `c0080 c0081`, and rewrites the new c0080's document in place. c0080 keeps its 2026-10-22 landing.
  - "reads each compaction's map whole at that commit, at the path the commit has it, and only at compactions": 5 reads, the first at `tracker/compaction.txt` and the next at `z-nile/compaction.txt`, and none at the map's move.
  - "without a map reader a compaction undates every item it touches, and warns".
  - A `model.spec` assertion that c0011, kept and rewritten in place at the fixture's compaction, is still dated from history. This pins `history.read`'s reader at its call site.

  Mutants:
  - M68 now judges by the diff;
  - M69, the union of every map read so far;
  - M70, `parse` reads the parent's map;
  - M71, `history.read` reads the parent's map.

  All four are killed, and the whole set of 71 was rerun. The removal mutant this round named, and the two equivalent mutants listed with it, have no code left to apply to; the rebuild is gone.

  Consequences:
  - One `git show` per compaction commit on a cold cache, which is one so far.
  - A shallow clone has no history at all, so it reads no maps.
  - `parse` stays pure with the reader injected.
- Lesson: the reviewer's candidate is a note on `tracker/item-history-spans-moves-and-compaction`: state rebuilt from diffs needs a case where a later diff removes what an earlier one added, and reading the state whole where it is written avoids the rebuild. It is harvested for F1, and the lesson's rule sentence now names the read at the commit.

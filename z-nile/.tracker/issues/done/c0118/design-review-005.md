# Review 005: c0118 (design mode)
Inputs: `prep-c0118` at 92b5e53b (`c0118.md`, `check.sh`, `acceptance/history.spec.luau`, `acceptance/model.spec.luau`, `prototype.patch`, design-review-004 and design-refute-004); the prototype `proto-c0118` at 7c6e074e, cloned into the scratchpad; a full clone of the real repository at d3d8f137, and a blobless partial clone of it.
Dropped from review-004: F1. The rebuild is gone, as the refute says: `applyMaps`, `contentOf` and the map state are deleted, and `renamedIds` reads each added or changed map whole through `readMap(sha, path)` and `ids.parseMap`. The prep folder's `c0118.md`, `check.sh`, history and model specs, and the `history.luau` part of `prototype.patch`, are identical to the prototype's.

Verified:
- **The map's path at old commits.** `readMap` gets the path from the commit's own diff (`b/<path>`) and that commit's sha. On the spec's fixture, the first read is at `tracker/compaction.txt` and the later ones at `z-nile/compaction.txt`. The byte-identical move is not read. On the real tree, the one read is the 2026-10-05 compaction at `tracker/compaction.txt`.
- **One commit that moves and edits the map** (a handwritten fixture: `git mv tracker/compaction.txt z-nile/compaction.txt`, then a new map `c0009 c0005`, with both item documents moved between roots and rewritten). `isCut` sees different content and calls it a compaction. The deleted side is skipped, and the map is read once at the new path at that sha. c0005 is undated, and c0007, which is kept, keeps its 2026-10-01 landing.
- **A map deleted at a commit** (same fixture; the commit also rewrites c0007). Deleting the map is no compaction: there is no read and no warning, and c0007 keeps its date.
- **`git show` failing.**
  - At the parse level: a reader that returns nil for the compaction's sha gives one warning, and every item the commit touches is undated (c0005 and c0007). That is fail-closed.
  - In a blobless partial clone with the promisor unreachable, `git log -p` fails before any `git show` runs, because the log's diff needs the same map blob. `history.read` returns nil, and the board falls back to spend dates.
  - With the promisor reachable, the clone works: same results, 0 warnings, about 11 s cold, all of it the log's lazy blob fetches (c0073's existing cost). It makes one `git show`.
- **Performance on the real history** (cold, with no `.cache`): 1 `log`, 3 `rev-parse` and 1 `show` (the one compaction). `history.read` takes 0.66 s wall clock.
- **E1.** Round 4's `history.luau` (66afbca7) and round 5's give byte-identical `doneAt` and `activeAt` on the real tree (106 lines), with 0 warnings. c0114 and f0100 are dated as in round 4.
- **No regression.** `./zn check c0118`: 8/8 criteria pass, AC7's promoted board, Stats and c0073 history specs among them. The c0118 history and model specs and c0073's history spec pass 39 of 39.
- **`parse` stays pure.** It runs no process and touches no file. Its only I/O is the injected `readMap`, and without one it fails closed with a warning per compaction (the spec pins 5). `history.read` is still the only place that runs git, and its cache key is `v7`.

### F1 [low] The reader-returns-nil path is unpinned: a mutant that skips an unreadable map (no renames, no warning) passes every spec
Where: `history.luau` `renamedIds`; `acceptance/history.spec.luau`; AC2 ("a map that can't be read … undates every touched item with a warning")
Evidence: I added `if readMap and text == nil then continue end` after the read. The c0118 history and model specs and c0073's history spec pass 39 of 39. The "without a map reader" case covers only a missing reader. The real code is correct (checked above).
Critique: low, because the case is close to unreachable. Any git failure that leaves the map blob missing also fails `git log -p`, and then `read` returns nil. But AC2 names the case, and the mutant is cheap.
Consequences: none.
Recommendation: in the history spec, add a parse with a reader that returns nil for one compaction's sha. Expect one warning, and an item that commit touches to be undated. Add the matching mutant row.

### F2 [low] A map moved and edited in one commit is unpinned: judging a delete plus an add as a move by path instead of content passes every spec
Where: `history.luau` `isCut`; the spec's only move is byte-identical
Evidence: I made `isCut` treat any map delete plus add as a move, ignoring content. All 39 still pass. On my fixture, the real code reads that commit as a compaction and undates the renamed id. The mutant would silently keep its stale landing.
Critique: low, because the one move (c0114) has landed, so a move and a compaction in one commit is unlikely. The rule, "a move is no compaction, judged by content", is still stated without a case that tells the two apart.
Consequences: none.
Recommendation: add a fixture commit that moves the map and changes a pair, and expect that pair's ids to be undated. Add the mutant row, "a map delete plus add is always a move".

Lesson candidate (for the lead): when a fail-closed branch has two triggers (no reader, and a reader that fails), each trigger needs its own case. Check: does any fixture take each trigger separately?

Verdict: approve

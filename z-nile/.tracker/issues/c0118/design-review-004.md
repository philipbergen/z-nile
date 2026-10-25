# Review 004: c0118 (design mode)
Inputs: `prep-c0118` at b6dfee73 (`c0118.md`, `check.sh`, `acceptance/history.spec.luau`, `prototype.patch`, design-review-003 and design-refute-003); the prototype `proto-c0118` at 66afbca7, cloned into the scratchpad (fix delta against round 3's 8c5e31f0: `history.luau`, the history spec, `c0118.md`); a full clone of the real repository at d3d8f137.
Dropped from review-003: none. F1 and F2 are fixed as the refute says. The prep folder's `c0118.md`, `check.sh`, history spec and the `history.luau` part of `prototype.patch` are identical to the prototype's.

Verified:
- **Both halves of the pair rule.** Deleting `out[old] = true` (M66) fails "both sides of a pair reset…". Deleting `out[new] = true` (M67) fails 5 cases. Judging by the diff again (M68) fails "a pair the next compaction repeats…". The c0118 history, model and real specs, c0073's history spec and c0119's capture spec all pass on the unmutated code (48 of 48).
- **A map deleted, then re-created** (handwritten fixture). The delete clears the rebuilt map, and the re-add is a compaction judged by its own content alone. c0005, named in the new map and touched by that commit, is undated. c0007, named only by an earlier map, keeps its landing.
- **A hunk that rewrites only the header.** It counts as a compaction over the whole map, but only for the ids the commit touches. The spec's "compaction map B" pins this. It is conservative, and it agrees with trail, which also marks the c0119 header-edit-plus-document case.
- **The c0114 move, squashed with other changes, on the real tree.** 05b058ea (R0043, 976 files) deletes `tracker/compaction.txt` and adds `z-nile/compaction.txt` with byte-identical content. `isCut` sees a move, and c0114 is dated at that very commit (2026-10-23T23:41Z). The rebuild keys its state by path. The delete clears the old path, and the add starts the new one from its full content.
- **A history that starts partway through the map's life.**
  - `history.read` returns nil in a shallow repository (`--is-shallow-repository`), so the board falls back to spend dates and says so.
  - A blobless partial clone has the full commit graph.
  - A history cut short some other way (a graft, or a filtered root) starts at a root commit, which adds the whole map, so the rebuild is correct there too.
  - The refute's wording ("a shallow clone has no history at all") is loose, but its conclusion holds.
- **Non-linear history** (a remap branch that merged origin/main, as `remap` tells it to). Both sides change the map. On a fixture, git's default history simplification shows only one side's edit, because the merge is TREESAME to the branch. No line is counted twice and no warning is raised. Later dates match the linear case.
- **E1 on the real tree.** Round 3's and round 4's `history.luau` give byte-identical `doneAt` and `activeAt` (106 lines), with 0 warnings. Since round 3, main has moved on: c0114 has landed (2026-10-23T23:41Z) and f0100 is dated. Both versions agree on both.
- **No regression.** The delta touches only `history.luau` (`applyMaps`, `contentOf`, `renamedIds` reading the rebuilt content, cache key `v6`), the spec and the document. A `v5` cache is refused by its key.

### F1 [medium] The rebuild's removal of lines is unpinned: if a hunk's `-` lines are never applied, the rebuilt map becomes the union of every map ever written, and every spec still passes
Where: `history.luau` `applyMaps` (the `for _, line in m.minus` loop); `acceptance/history.spec.luau`; the Rules and mutants table (M68 is the only row for the rebuild)
Evidence:
- **The mutant.** I replaced `m.minus` with `{}` in `applyMaps`. The c0118 and c0073 history specs pass (20 of 20). The spec's second compaction repeats MAP_A word for word, and its broken map adds a line. Neither drops a pair, so the removal half is never exercised.
- **Handwritten fixture:**
  - Compaction 1 maps `c0007 c0002`.
  - A new c0007 lands on 2026-10-05.
  - Compaction 2 maps only `c0009 c0008`, and rewrites c0007's document in place, as `compact` does for documents that name a renumbered id.
  - The real code keeps c0007 at 2026-10-05. The mutant undates it.
- **On the real tree** the mutant changes nothing today, because there has been only one compaction. At the next compaction, every kept item that the 2026-10-05 map names and whose document compaction 2 rewrites would lose its date. That is the defect §5's "An id the compaction keeps keeps its dates" rules out.
- Two other mutants survive, but they are equivalent, so they are not findings: "a delete keeps the state" and "an add starts from the old state". Each one is covered by the other step.

Critique: the refute moved from a stateless rule (judge each commit's diff) to state accumulated across the whole log. That state's correctness now rests on removal, and no case drops a pair. This is the third round in a row that finds a hole in how a compaction's renamed set is computed. The tempting fix is one more fixture commit. It is right, but it leaves a stateful reconstruction whose every step needs its own case.

Consequences: with the case and its mutant, none. If the author instead reads the map at each cut (`git show <sha>:<map>`, review-003 F2's first option), the state, `applyMaps`, `contentOf` and this mutant all go away. In exchange, the log format needs `%H`, and `history.read` runs one extra git call per compaction. `parse` would then take the maps' contents as input, to stay pure.

Recommendation:
- Add a history.spec case: a later compaction whose map drops a pair of the earlier one, and rewrites in place the document of an id that only the earlier map named. That id keeps its date. On the spec's fixture, this could be a third compaction that maps only an unrelated pair and rewrites the new c0080, which landed on 2026-10-22.
- Add mutant M69, "a hunk's removed lines are ignored", run and killed.
- List the two equivalent mutants as `reasoned`.
- Alternatively, replace the rebuild with a read of the map at each cut, and keep M68's case.
- Lesson candidate (for the lead to harvest): state rebuilt from diffs needs a case in which a later diff removes what an earlier one added. Check: does any fixture make the rebuilt state shrink?

Verdict: changes

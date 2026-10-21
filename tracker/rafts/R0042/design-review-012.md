# Review 012: R0042 (design mode)
Inputs: prep-z-nile at ef879b8 (R0042.md, check.sh, harvest.md, design-review-006 to 011 and design-refute-006 to 011; c0111 and c0119 documents, check.sh files and acceptance specs; the diff 136cb05..ef879b8). The prototype `.worktree/proto-scope-fidelity`: both member folders are byte-identical to this tree. I read its `scripts/tracker/trail.luau`, `cmd.capture`, `cmd.compact`, `cmd.remap`, `cmd.land` and `ids.parseMap` against the Design. The programme reviews of c0114 to c0118 and c0120 were read only for conflicts with R0042.
Round 011's refutation holds for its map-only scenario and for the removed-then-reused id: a commit that changes only the map changes no document, so it starts no life, and a reused number is a new life. F2 of round 011 is fixed. Settled user decisions are not reopened. F1 below is the sixth hole in the trail's identity rules (007 F1, 008 F1, 009 F1, 010 F1, 011 F1). It concerns how a commit is recognised as a compaction, which round 011's Recommendation also covered ("an unreadable map … stops the walk and sets a flag"; "the map file re-added at another path") and its answer left out.

Run on the prototype:
- c0111's and c0119's acceptance specs: `65 passed, 0 failed, 11 spec files`.
- `luau-lsp analyze` of `trail.luau` and both acceptance folders: exit 0.
- `lessons --check`: `21 lessons, 102 harvest entries, ok`.
- `capture c0111` and `capture c0119`.
- Three scratch fixtures (git repositories under the review's scratch directory, each with a copy of the prototype's `scripts/`), each running `scripts/tracker.sh capture` (F1). A fourth, with two real compactions, gave the right capture for both items.

I didn't run `promote-check`.

Lessons pass (item 10, `lessons --when design --full`):
- Failed: `tracker/item-history-spans-moves-and-compaction` ("its id before each compaction"). The trail counts every commit that touched `tracker/compaction.txt` and changed the id's document as a compaction (F1).
- Failed: `architecture/parsers-refuse-ambiguity`. At a cut, an unreadable or deleted map is read as "nothing was renamed onto this id", so the walk goes on as if it were the same item. It neither refuses nor marks (F1).
- The others pass or don't apply:
  - `no-vacuous-pass`: the marker cases assert both that the marker is present and that it is absent elsewhere.
  - `one-reader-per-format`: the trail uses `ids.parseMap`.
  - `guards-trust-only-origin`: `capture` reads `origin/main`.
  - `new-rules-migrate-existing-work`: ready-raft's scope step, settled by a decision line.
  - `never-narrow-captured-scope` and `no-scope-cut-as-fix`: see item 11.

Scope fidelity (item 11, against the prototype's `capture`):
- c0111 (`ef5a7a5 tracker: new c0111 Skill lessons`, unmarked): since round 011, no change to the title, Problem or Solution, only to the Design. Round 011's comparison still holds: the Problem gained only the `Scope decision` lines, the Solution bullets are verbatim, and every outcome has a Design and a criterion.
- c0119 (`ab750c0 tracker: new c0119 c0120; …`, unmarked): the title, Problem, Non-goals and Solution are the capture plus the `Decided with the user (2026-10-20)` block. The changes since round 011 are in the Design, the Appendix and the experiments only.

### F1 [medium] A cut is any commit that touched `tracker/compaction.txt`, and a cut with an unreadable map counts as "nothing renamed onto this id". A doc edit committed with a map edit, a revert of a compaction, or an unparseable map gives another item's capture with no marker
Where: c0111 The trail, **read** ("a compaction commit (one that changed `tracker/compaction.txt`) whose map renames something onto the id"), **since**, **crossing**, and the row "only a compaction commit is crossed" (`reasoned`: "the document proof also stops it"); prototype `trail.read` (`cuts`, `mapAt`, the `since` predicate); c0119 Design (`capture`), the tracker skill's `capture` row
Evidence:
- **A map edit and a document edit in one commit cross into a rotated item.** Fixture 1:
  - `tracker: new c0010 Alpha` and `tracker: new c0140 Pi` are committed;
  - `tracker: compact ids` renames c0010 to c0001 and c0140 to c0010 (a rotation: Pi's document replaces Alpha's at c0010's path);
  - a prep edits c0001.

  At this point `capture c0001` correctly prints `tracker: new c0010 Alpha`. Then one commit fixes the map's `#` header and also edits c0001's document, as a squash-merged PR that touches both would. After it, `capture c0001` (Alpha) prints:
  ```
  capture 11a425e… tracker/issues/c0140/c0140.md tracker: new c0140 Pi
  # c0140 PI captured
  ```
  There is no marker. That commit is a cut, it changed c0001's document, and its map (the same map) renames c0010 to c0001, so `since` starts a life there. `crossing` then finds that c0010 held a document just before the commit. It did, but the document was Pi's, rotated there by the earlier compaction. The walk crosses into c0010 and from there into c0140. The "document proof" can't tell a compaction from a commit that carries an old map, because after a rotation the old id's path always holds a document. So the `reasoned` row's premise is false.
- **An unreadable map is read as continuity.** Fixture 3 is the same rotation, but its map has one line `parseMap` refuses (`R0010 c0002`, a prefix change). `capture c0010` (Pi) prints `tracker: new c0010 Alpha` with no marker. `mapAt` returns nil, so `since` never narrows, and Pi's life under c0010 runs back into Alpha's. A reverted compaction does the same: the revert deletes the map, so `git show <revert>:tracker/compaction.txt` fails, and the revert's rotation back is invisible. After a revert, the item back at c0010 (Alpha) gets the life the earlier compaction started, which is Pi's.
- **Where this happens:**
  - Squash merges (`gh pr merge --squash`, and `land`'s `commit-tree`) make every PR one commit, so a PR that edits the map and any document produces this commit.
  - c0114, next in the chain, moves the tracker and its map into `z-nile/.tracker/` (programme review c0114 F6, F7(b)). Its move commit adds the map at the new path with the last compaction's content, and it moves every document. Once `trail.dirs` covers both roots, which c0111 says c0114 adds, that commit is a cut that changed every document, with a map that renames onto every rotated id. Every item whose old id was reused by the compaction then gets another item's capture, unmarked.
  - GitHub's Revert button on a compaction PR is the revert case.
- **No case covers these.** `capture-cli.spec`'s `mapedit` case changes only the map. No case has an unreadable or deleted map at a cut, or a cut that also edits a document.

Lesson: tracker/item-history-spans-moves-and-compaction, architecture/parsers-refuse-ambiguity
Critique: Round 011 moved identity onto the document, but whether a commit is a compaction is still inferred from where it is: any commit touching the file is believed, and a map that can't be read is taken as a "no". The tempting fix is to require the old path's deletion, or to skip a cut whose subject isn't `tracker: compact ids`. The first was round 011's first version, which failed on the real rotation (E6). The second trusts a subject that a squash merger types by hand.
Consequences:
- A compaction has to be recognised by its content, and every other cut that changed the id's document has to stop the walk visibly. That adds a third marker, which ready-raft and item 11 already treat as not matching. c0114 must hand the trail every path the map has had, or its move commit stops every walk. That stop is marked, so it is safe, but it is noisy.
- It costs one more cached `git show` per cut (the map at `<cut>~1`), with one or two cuts today.
Recommendation:
- **A cut is a compaction only when its parsed map differs from the parsed map at `<cut>~1`** (a map absent at `<cut>~1` counts as different). A cut whose map parses the same as its parent's is not a compaction: read straight through it under the same id. That covers the header edit and c0114's copy of the map to a new path, provided the trail reads the parent's map at the map's earlier path.
- **A cut with no readable map** (unparseable, or deleted, as in a revert) **that changed the id's document stops the walk.** `capture` prints that commit's document with ` (ambiguous: unproven compaction at <sha>)`, never the history before it, and never exits 1 for "no history".
- `crossing` stays as it is, but only for cuts that pass the first rule.
- **Text:** the trail's **read** and **since**, c0119's marker list, the tracker skill's `capture` row, and the lesson's `check` ("each compaction, recognised by its map changing"). Replace the `reasoned` row "only a compaction commit is crossed" with run rows.
- **Spec cases** (`capture-cli.spec` end to end, `trail.spec` for the pure predicate):
  - a header-only map edit in the same commit as a document edit of a rotated item: its capture is unchanged;
  - a compaction whose map does not parse, with a rotation: marked, never the previous item's text;
  - a revert of a rotating compaction: marked;
  - two real compactions still cross (already seeded).
- **Mutants:** "every map-touching commit is a cut", "an unreadable map renames nothing", "compare raw text instead of the parsed map" (killed by the header-plus-edit case).
- **c0114:** add a pointer in its Design that the trail must be given the map's earlier path when the map moves. This adds no scope.

### F2 [low] The prototype's header comment describes the rejected proof
Where: `scripts/tracker/trail.luau` lines 4–6 ("and the same commit deleted the document from one of the old id's folders")
Evidence: the Design's **crossing**, and the code below that comment, prove a crossing by the rename plus the old id's document before the commit: "It is not a deletion, because a rotation leaves the old path holding another item". The comment still describes the deletion proof that E6 rejected. An executor who copies the prototype carries the stale rule into the delivered module.
Recommendation: reword the comment to match **crossing** (and F1's compaction rule, once it is fixed).

Verdict: changes

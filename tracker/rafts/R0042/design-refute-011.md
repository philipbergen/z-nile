# Refute 011: R0042
Round 011 is this re-prep's round 6, run at the user's request to "keep going until the review approves". It had no high finding. Round 012 follows.

Verification on `.worktree/proto-scope-fidelity`, synced with this tree:
- `scripts/check.sh --full` printed `GATE PASSED (full)`. Its first run's type check caught an unused helper in `trail.spec`, now removed.
- c0111's `check.sh` passed 11/11, and c0119's passed 4/4.
- `promote-check R0042` printed `promote-check OK`.
- `luau-lsp analyze` of both acceptance folders and `scripts` exited 0.
- `lessons --check` printed `21 lessons, 102 harvest entries, ok`, and `--uncovered R0040 R0042` printed that every finding is covered.

- F1: fixed, by changing the rule as recommended. This is the fifth round on the id rule, and every earlier rule inferred an item's identity from ids.
  - The trail no longer walks ranges between cuts. It keys an item's life to its document: `trail.life` starts a life at the last commit that took the id from no document to one, with each commit applied as a whole, so a move or an in-folder rename is not a start.
  - `trail.since` also starts a life at a compaction whose map renames an old id onto this one, because compaction rotates ids. On the real tree, c0041's old path held c0410's document after the compaction.
  - The walk crosses back only when `trail.crossing` proves it: the map names the rename, and the old id had a document just before the commit.
  - So a commit that edits only the map starts no life and is never crossed. A reused number without a capture commit is a new life, which gets the marked first-add fallback. Neither fixture from this review can produce another item's capture.
  - `capture-cli.spec` adds a removed-then-reused id, a rotating compaction, a map-only edit, and a renamed item that is later removed and re-added. `trail.spec` pins `life`, `since`, `crossing` and `ambiguous`.
  - On the real tree, `capture` over the 150 items named no other item's capture: one is marked ambiguous (c0004) and 98 first-add.
  - consequences: one `git ls-tree` per crossing, plus a cached `git show` of the map. The mutants (first-ever add as the start, no narrowing, no document proof, a move as a start, no ambiguity) each failed a case. "Cross at any life start" is equivalent while the document proof holds, which E6 records.
  - c0114, which moves the roots, extends `trail.dirs`, as its programme review (F6) says.
- F2: fixed: in ready-raft, a marked capture counts as not matching "until the Problem has a `Scope decision (user, …)` line that confirms the item's scope". The spec pins it, and the mutant that drops the clause is killed. consequences: R0012's three members, which are marked today, need one decision each, once.

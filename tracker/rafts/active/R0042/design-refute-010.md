# Refute 010: R0042
Round 010 is this re-prep's round 5, the last that ticket-prep allows. It had no high finding. The user asked on 2026-10-20 to "keep going until the review approves", so a further round follows these answers. R0042's Risks records this.

Verification on `.worktree/proto-scope-fidelity`, synced with this tree:
- `scripts/check.sh --full` printed `GATE PASSED (full)`. Its first run caught a literal legacy name in a new `trail.spec` case, which the c0044 guard refuses; the case now builds it by interpolation.
- c0111's `check.sh` passed 11/11, and c0119's passed 4/4.
- `promote-check R0042` printed `promote-check OK`.
- `luau-lsp analyze` of both acceptance folders and `scripts` exited 0.
- `lessons --check` printed `21 lessons, 99 harvest entries, ok`, and `--uncovered R0040 R0042` printed that every finding is covered.

- F1: fixed, by changing the mechanism. This was the fourth round to find a hole in the trail's id inference, and F1 shows the ledger can name the wrong item.
  - The renumber ledger is gone: `renumber` writes nothing new, and the trail no longer reads renumber cuts, `trail.added` or `dirs`. Ids are followed only through compactions. A compaction is one commit on `main` with a complete map, so it is authoritative.
  - What the trail cannot settle is now marked, never inferred:
    - a renumbered item's capture is its first add at the new id, marked `(no capture commit: first add)`;
    - an id that two items held at once (the collision flow) is marked `(ambiguous: two items held this id at once)`, using the new `trail.ambiguous`.
  - ready-raft counts a marked capture as not matching, so the user is asked. Item 11 says to judge such an item's scope from its history.
  - On the real tree: `capture` over all 150 items on `origin/main` marked one as ambiguous (c0004, the old c0040 collision) and 98 as first-add (older items and every raft).
  - consequences: renumbered and older items get a weaker baseline, but a visible one, and the user decides those cases at ready. None of F1's three wrong-item scenarios can occur, because nothing is replayed. The 8 mutants (additions before deletions, span id ignored, never ambiguous, no ambiguity marker, no first-add marker, and the ready-raft, item 11 and tracker-row text) each failed a case.
- F2: refuted as moot: the ledger it concerns no longer exists. Its claim that `compact` doesn't rewrite `.txt` files was right, and that row is gone too.

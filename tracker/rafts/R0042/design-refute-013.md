# Refute 013: R0042
Round 013 is this re-prep's round 8. It had no high finding. Its F1 escalated the identity rule to the user, and the user chose "Never cross; mark it" (2026-10-20).

Verification on `.worktree/proto-scope-fidelity`, synced with this tree:
- `scripts/check.sh --full` printed `GATE PASSED (full)`.
- c0111's `check.sh` passed 11/11, and c0119's passed 4/4.
- `promote-check R0042` printed `promote-check OK`.
- `luau-lsp analyze` exited 0.
- `lessons --check` printed `21 lessons, 106 harvest entries, ok`, and `--uncovered R0040 R0042` printed that every finding is covered.

- F1: fixed (user decision, 2026-10-20: "Never cross; mark it").
  - The trail follows the item's current id only. `trail.crossing`, `trail.sameMap` and the real-versus-unproven split are gone.
  - A commit that changed `tracker/compaction.txt` and the item's document starts the item's life, and `capture` marks it `(history before <sha> not followed: it changed tracker/compaction.txt)`. That commit may be a compaction, a revert, a restore, a header edit or a broken map; none of them is followed and none can name another item.
  - The tracker skill's row and c0119's Design list the markers. A marked capture counts as not matching at ready until a `Scope decision` confirms it.
  - consequences: about 130 of 150 items on today's tree are marked (from before the 2026-10-05 compaction). Of those, only c0075 and c0083 are open, and they are already in the one-time audit. c0114's moves must keep the item ids, which they do, since a move between roots is a folder move. Metrics dates a renumbered raft from its compaction, which predates lessons, so it still counts as "before". The two mutants (no narrowing, which follows a rotation back; no note) were killed.
- F2: fixed: the reasoned row on crossing is gone, together with the crossing it described. c0111's rows now cover the life start, narrowing at a map-and-document commit, and the marker. consequences: none.

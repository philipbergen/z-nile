# Refute 014: R0042
Round 014 is this re-prep's round 9. It had no high finding.

Verification on `.worktree/proto-scope-fidelity`, synced with this tree:
- `scripts/check.sh --full` printed `GATE PASSED (full)`.
- c0111's `check.sh` passed 11/11, and c0119's passed 4/4.
- `promote-check R0042` printed `promote-check OK`.
- `luau-lsp analyze` exited 0.
- `lessons --check` printed `21 lessons, 108 harvest entries, ok`, and `--uncovered R0040 R0042` printed that every finding is covered.

- F1: fixed:
  - Metrics no longer reads the trail. It dates a raft by `lessons.day` of its `created:` frontmatter, which no compaction or renumber rewrites. The cutoff is the UTC day `scripts/tracker/lessons.luau` was added (`git log --follow`, since the file has a unique history).
  - `metrics-lessons.spec` adds a pure `lessons.day` case. The fixture now has three rafts:
    - R0010 and R0020, created in 2099, whose reviews landed in the seed commit;
    - R0030, created in 2020, with every commit made today;
    - a compaction-like commit that rewrites R0020's review in place.
    So history dating and `created:` dating disagree on two rafts.
  - On the real tree all 41 rafts are dated (`before | 41 | 173 | 4.2`); history dating had dated 39.
  - consequences: c0114 passes the module's new path when it moves the engine (c0111 Design). The mutants (date by history; compare seconds with days) were killed.
- F2: fixed:
  - ready-raft and item 11 now say "any marker", naming all three: `(no capture commit: …)`, `(ambiguous: …)` and `(history before … not followed: …)`. The spec pins both.
  - The stale passages are rewritten or marked superseded: c0111's Solution and reader, E5 to E7, c0119's Scalability and rows, the AC4 label in c0119's `check.sh` (sequestration doesn't apply until the raft is readied), R0042's Whole-raft design, and the prototype's `cmd.capture` comment.

  consequences: none.

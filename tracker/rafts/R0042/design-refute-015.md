# Refute 015: R0042
Round 015 is this re-prep's round 10. It had one high finding, so another round follows.

Verification on `.worktree/proto-scope-fidelity`, synced with this tree:
- `scripts/check.sh --full` printed `GATE PASSED (full)`.
- c0111's `check.sh` passed 11/11, and c0119's passed 4/4.
- `promote-check R0042` printed `promote-check OK`.
- `luau-lsp analyze` exited 0.
- `lessons --check` printed `21 lessons, 111 harvest entries, ok`, and `--uncovered R0040 R0042` printed that every finding is covered.

- F1: fixed with the reviewer's tested fixture, plus a type annotation that `luau-lsp analyze` required.
  - The fixture's clone amends the seed so `scripts/tracker/lessons.luau` is not in it (dated 2020), then commits that file dated 2030-06-01.
  - Three rafts sit around the cutoff: one created 2030-05-31 (before), one on 2030-06-01 (after, at the boundary) and one in 2099 (after).
  - The three cutoff mutants (the clock, HEAD's commit, the first commit) each fail, and the intended reader passes. A row records them.
  - consequences: none beyond the fixture.
- F2: fixed:
  - AC9 now states the `created:` dating rule and the 2030-06-01 boundary, and no longer the removed history case.
  - The trail paragraph says metrics doesn't use the trail, and step 7 says it dates by `created:`.
  - The Output heading matches what the prototype prints.
  - The Test plan lists the `day` cases.

  consequences: none.
- F3: fixed:
  - `lessons.day` keeps its range check and delegates the arithmetic to `stats.day`, newly exported from `stats.luau`'s `toDays` (one reader per format). `stats.luau` joins Touched modules.
  - The cutoff is now the local calendar day of the `lessons.luau` commit, the same calendar `created:` is written in (`os.date("%Y-%m-%d")`), so a raft created on the day lessons land is always "after".

  consequences: `stats.day` is a new export that the board's own code doesn't use; c0042's board specs passed in the full gate.

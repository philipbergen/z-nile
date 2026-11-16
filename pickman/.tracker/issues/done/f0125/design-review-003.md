# Review 003: f0125 (design mode)
Inputs: prep-player-faster 75c9cb81 (f0125.md, check.sh, acceptance/speeds.spec.luau, acceptance/docs.spec.luau, design-review-002.md, design-refute-002.md, harvest.md, z-nile/skills/zz-test/lessons/refusals-tested-on-both-sides.md); prototype `.worktree/proto-f0125` (base d24aabc8, uncommitted diff; its `tests/acceptance/f0125` is identical to the item's `acceptance/`). Experiments in a scratch clone (d24aabc8 + the prototype's diff + its specs), specs run singly.
Dropped from design-review-002: F1, F2, F3

Rulings on refute 002:
- F1 fixed. The case now accepts base 96 with k = 120/114 (level 5's ghost exactly 120), refuses 121/114, and accepts base 30 with k = 2 (71). In the scratch clone the prototype gives `9 passed`. Each mutant below was applied to `Session.new` and run with `lune run tests/run -- tests/acceptance/f0125/speeds.spec.luau`, and each gave `8 passed, 1 failed` on "a ghost tuning that would move a ghost more than one tile a tick is refused …":
  - `>=` for `>`;
  - KGT1 (`k > 1` refused, the loop disabled);
  - the loop over level 1 only;
  - an off-by-one the other way (`v > UNITS + 1`).
  `docs.spec` gives `2 passed`. The "normal only" equivalence holds by reading: `speedFactor` exceeds `tunnelFactor` and `frightFactor` in every row.
- F2 fixed. The bound resolves `k or Levels.GHOST_TUNING` (prototype `local tuning = k or Levels.GHOST_TUNING`), and its message still prints the configured `k`. Skipping untuned configs is correctly recorded as equivalent while GHOST_TUNING is 1.
- F3 fixed. The harvest names the new lesson. That lesson is general: any refusal with a bound, in any raft, can fail it. It is not a restated finding.

No new findings.

Verdict: approve

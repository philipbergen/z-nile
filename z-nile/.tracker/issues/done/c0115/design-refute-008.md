# Refute 008: c0115 (design mode)
Answers `design-review-008.md`. The base is unchanged: bc550e9.

- F1: fixed: every template section of c0113's document is filled:
  - Scalability, Maintainability and Usability: none of its own; c0115's raft does the work;
  - Affected specs: c0115's `readme.spec` and its case "covers every ask of c0113";
  - Unknowns: none;
  - the Regression guard, with `Overrides: none` (c0115 owns the deletion and its overrides);
  - a Test plan;
  - two Rules rows: the README case, whose mutant is a README missing the stop edge (reasoned, pointing at c0115's M27 and M28), and AC2, whose mutant is `.claude/README.md` restored (run in round 7: red);
  - AC1 and AC2 under Checked, in `check.sh` order; Judged and Observed: none;
  - Implementation steps: "None of its own: c0115's raft does the work, and `./zn done` closes c0113 with it".

  A sweep of c0113's and c0115's documents and `check.sh` files finds no placeholder left (`<!--`, `<promoted specs`, `<statement>`).
- F2: fixed: `engine.copy` now reads `engine.COPIED_SKILLS`. It skips `z-nile/skills` in its loop over `z-nile/` and copies each folder of the list, with its lessons. `clearLessons` and c0115's G7 case read the same list. M54 and M55, rerun against the committed code: killed.

Checks on the prototype after the change:
- `z-nile/check.sh --full`: GATE PASSED, pickman 1068 and z-nile 997 cases, 174.8 s at load average 25;
- `./zn check c0115`: 13/15 (AC12, the freeze, and AC15, no raft formed yet, are red for the right reasons);
- `./zn check c0113`: 2/2.

A slip on the way: the mutation runner restores the files it mutates with `git checkout`, and I ran it before committing the F2 edit, so the edit was reverted. I caught it by grepping for the change, reapplied it, committed, then reran. The note is harvested under ticket-prep/rerun-skipped-checks-after-edits: commit before any tool that resets files.

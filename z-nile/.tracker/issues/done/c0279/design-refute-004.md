# Answers to design-review-004 (c0279)
- F1: fixed: Rules row and mutant M11 (the runner ignoring the tool limit; TBD result in the issue); the margin (12 s quiet over a 10 s stall limit) is stated and left to the user to lengthen.
- F2: fixed: the CLI fake's first line is `[ -z "${FAKE_DELAY:-}" ] || sleep "$FAKE_DELAY"` (a builtin, nothing spawned when unset), pinned exactly; the three other specs were run once on the final prototype (E6); Existing work and E6 corrected; c0287 named. Lesson: zz-test/shared-fake-knobs-spawn-nothing-when-unset.
- F3: fixed: c0194's lesson restored from origin/main, its check widened, c0279 added as a note.
- F4: fixed: claims updated for the decision (Non-goal, Why this holds, Scalability with the +33 s and the AC2 cost).
- F5: fixed: steps, golden length (84), size 50, comments, E3/E4/E8 wording, E4b log saved.
- F6: fixed: pins.sh pins the exact first line.
- F7: acknowledged: PR #274 is updated with this commit and is not to be merged before the coordinator reads the final report.

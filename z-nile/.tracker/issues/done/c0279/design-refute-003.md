# Answers to design-review-003 (c0279)
- F1: fixed: the first-match edit hit `runner.luau` line 141; M8 rebuilt with unique-pattern edits read back in the fixture (`grep -c` printed 1); M8 fails `stalled`, M8b (hold 20 s) passes: the hold kills the mutant. Rows split (M8/M8b and M1); the two invalid logs deleted. Lesson: z-design/read-back-every-prototype-edit.
- F2: fixed: the Problem line marks the coordinator's relay; Non-goal and E5 reworded (run B's heartbeat stall named, both exposed windows named, "ready waits for the user"); the options stay.
- F3: fixed: constants (120 s and 240 s), golden diff 75 lines, "cannot be reached" reworded, pins.sh comment.
- F4: fixed: Rules rows for the wall-clock bound, the pid-file wait, the exact-text pins; `experiments/pins-wrong-fakes.txt` is the three wrong fakes.
- F5: fixed: spend rows recorded, status set at the end.
- F6: fixed: the Design names the pid-reuse false red.

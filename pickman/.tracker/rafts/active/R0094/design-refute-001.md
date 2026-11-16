# Answers to design review 001 (R0094)

The review read the record `[f0143@9de19e99185d, f0147@deb99c51e2b8, f0158@59277d5ddbf9]`, which is still the record. All five findings are accepted and fixed in R0094.md. No member is unfolded now, and no member's design changes. The Order section was also rewritten so that it names each member once and no other item id. R0077's review found that `stack.order` refuses anything else (lesson z-raft/order-names-members-once), and this Order named f0146, d0151, c0176 and others.

### F1 [medium] grouping makes f0143's and f0158's dependents wait on c0176 and c0177: fixed
Cross-raft waits now lists each dependent's added wait (d0149/R0066 and c0182 wait for c0176 and c0177 through f0147; c0196 and R0095 need f0147 anyway). It also states the fallback, its trigger and who takes it: the lead who readies R0094 runs `./zn unfold R0094 f0147` when c0176 or c0177 is not done and the rest is ready. R0095 says that it then waits for whichever raft holds f0147.

### F2 [medium] the members' sequestered specs have not run with each other's code, and two prototypes are gone: fixed in the text
Whole-raft design gains "Indirect spec reads": the three cross-reads, the property each relies on, and the stop rule (a red member is unfolded, and neither executor edits the other's spec). The Experiments phase says which prototypes are gone. The cheap stacked run (f0147's patch with f0158's place.spec) was not made at rafting time. f0158's DangerHud diff is not available as a patch, so the pair cannot be run without rebuilding f0158's prototype. The stop rule covers it.

### F3 [medium] the Exit criteria point to an RC1 in the lead's report: fixed, option (c)
The pointer is gone. Exit criteria now names the two unpinned claims (a boost on the shipped ramp; the PICKS row against the ring), what each rests on, the code-review check for the first, c0196 for the second, and why that is acceptable now. No RC line is added. A raft-owned spec has no home the runner and `promote-check` accept, and option (b) would need c0196 prepped first.

### F4 [low] the smallest ramped gain is on levels 1 and 2: fixed
Experiments phase restated with the review's numbers: 14 units a step on levels 1 and 2 (308 units, 2.57 tiles; about 1.9 tiles in a dotted corridor), above E1's 240. The gain peaks near 50 at level 29 and falls to 30 at level 34.

### F5 [low] stale or missing facts: fixed
f0147's game-design text is on main (e3eae83c), so only f0143 adds a section, and that section states the boost relative to the level's speed or gives both level-1 figures. `tests/place/touch-adapters.spec.luau` is named beside `hud-shots.spec.luau`. f0143's E7 is carried into Cross-raft waits as a pre-z-ready check, with today's result (pass, `Controls.luau:188-196`) and its fallback.

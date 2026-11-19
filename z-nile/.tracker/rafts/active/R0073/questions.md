# R0073: questions

## Q1: May c0178's sequestered harness spec stop counting the runner's PASS lines?

c0178 is 9/10 on current main. The one red criterion is AC4, and no code change can make it green.

- The case: `acceptance/harness.spec.luau` :: "the coordinator of a concurrent run sums its workers' counts and prints them once, between slowest: and the summary", lines 214-220.
- What it pins: the run prints exactly three lines (`slowest:`, `fixtures:`, the summary), by position.
- What changed: since 2026-11-09 (9738540ed, "Speed up affected spec gates") main's coordinator also prints one `PASS <file>: N passed, 0 failed` line per spec file, so a two-file run prints five lines. The spec was written 2026-11-01.
- Why the code cannot give way: the promoted spec `tests/acceptance/c0049/parallel-runner.spec.luau:365` pins those `PASS` lines, and it is in AC10's sample.
- What is right today: the `fixtures:` line holds the summed counts (14 files, 6 processes) and sits between `slowest:` and the summary, as the Design says.

Options:
1. Authorize the edit to the sequestered spec: drop lines that start `PASS ` or `FAIL ` before counting, then expect `slowest:`, `fixtures:` and the summary in that order with the same counts. The case still fails if the counts are printed twice, are wrong, or sit elsewhere. It changes c0178's contract, so `./zn approve c0178` is needed after it.
2. Send c0178 back to z-design for that one case (`./zn unfold R0073 c0178`), which costs a prep round and a re-rafting.

Recommended: 1.

# Answers to review 002 (R0140)

I checked each claim by running the specs. Correction first: the round-1 answer for F11 said the `par-stages` cases run under `set -euo pipefail`. That edit had silently not applied; it is now made and verified in the file.

- F1: fixed: new case `--jobs N is a cap` with three specs that each wait for the other two: `--jobs 2` must give exactly `1 passed, 2 failed, 3 spec files` and `--jobs 3` must pass all three. It kills an uncapped runner and a hard-coded 2. Consequences: the Rules row now says "at most and exactly `jobs`"; one more case with a 1 s timeout.
- F2: fixed: `sh()` now prefixes `set -euo pipefail` (verified in the spec source); consequences: `par.sh` must be safe under those options, already in the Rules row.
- F3: fixed: the all-pass six-file case asserts exactly two output lines (`slowest:` and the summary), a `slowest:` line with exactly 3 entries, and one summary line; consequences: the Rules row names the re-printed worker summaries and the uncapped list as mutants.
- F4: fixed: the scan covers `tests/` only (sequestered prep specs join the scan at promotion, where `tracker.sh done` runs the promoted specs and rolls back; a prep can no longer turn main red), a failure prints the colliding directories and files as a string, and the rule (a mere mention counts, `sim` exempt) is written in the testing-skill text the issue requires; consequences: a collision between two active rafts' prep specs is caught at `done`, not earlier (accepted).
- F5: fixed: the Speed rule now bans wall-clock *assertions* and fixed sleeps, and allows bounded polls and rendezvous with a timeout; consequences: none.
- F6: fixed: the Design requires a fresh `mktemp -d` per batch, removed by `par_wait`; new case `two gates running at once do not mix their output`; consequences: one row.

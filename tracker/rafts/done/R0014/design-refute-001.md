# Answers to review 001 (R0014)

Each fix ran the consequence step: what new rules, state, edge cases or decisions the fix brings. Rows and cases were added in the same change.

- F1: fixed: the `slowest:` case asserts both specs appear and that slow comes before fast, not that slow sits at position 1; consequences: none (the printed path form stays repo-relative).
- F2: fixed: every child run in `parallel-runner` sets `PICKMAN_JOBS` to empty, and the Design now says an empty value means unset; consequences: new rule "empty means unset, bad means exit 2", with a row and a case (`a bad PICKMAN_JOBS exits 2 ...`).
- F3: fixed: fixtures with 3, 1 and 2 cases (`5 passed, 1 failed, 3 spec files`); consequences: a row "counts are summed per case across workers".
- F4: fixed: the Design says each stage's time is taken inside its own subshell when it ends; the case starts a 2 s stage and a quick one and asserts the slow one reads at least 2 s and the quick one under 1.5 s; consequences: one new row; the 1.5 s upper bound is the only timing bound, set 6x above the stage's real cost.
- F5: fixed: new AC4a checks `check.sh` has five `par_start` lines all before its single `par_wait`; consequences: a structural (grep) check, stated as such in its row.
- F6: fixed: the once-marker is an atomic `mkdir`, so a second run of the same file fails even when two lanes race; consequences: none.
- F7: fixed: added a case for a worker that exits 0 without a summary and one that prints a summary and then exits 5 (the Design already said both are one failure); the in-process row now names the mutant and the assertion that kills it (exact stdout without `slowest:`); the CPU-count default is stated as not checked beyond 2 lanes (Design, "Not checked"); consequences: two rows.
- F8: fixed in part: timeouts cut to 1 s and sleeps to 0.6 s (about 5 s for the spec, below the 9.3 s floor, and the three specs run as concurrent workers); consequence: the Design states that the rendezvous cases need bounded waits by nature. Refuted in part: polling a marker file is the only deterministic way to prove concurrency without a wall-clock threshold, which is why the Speed rule forbids wall-clock *assertions*, not bounded waits.
- F9: fixed: the eager-start case polls up to 5 s for the marker instead of sleeping 0.5 s; consequences: none (a lazy mutant now fails in 5 s).
- F10: fixed: the Design pins an empty or invalid `PICKMAN_JOBS`, `slowest:` only on the coordinator path, `--jobs` anywhere among the arguments, worker stderr to the coordinator's stderr after that file's stdout, and the wall-time clock; consequences: one case covers env and argument position.
- F11: fixed: the `par-stages` cases run under `set -euo pipefail`; consequences: `par.sh` must be safe under those options (the Design row says so).
- F12: fixed: the premise is corrected in the issue and in the spec comment (model names are not unique; a collision could only rewrite a replay file written on failure, so the exemption stays); consequences: none.

# Design refute 004

- F1: fixed: the stderr assertion is replaced by `t.expect(r.code).toBe(1)` (the copied runner's own failed case; exit 2 is a refusal) and the redundant `r.ok` line is gone; E5 records why and a mutant row names "the case accepts a refusal as the failure"; consequences: none (the exit code does not depend on the caller's CPU limit).
- F2: fixed: E5 names its `./zn run --time 600 -- bash …/experiments/E5-unmeasured-reexec.sh "$PWD"` command and the script is kept under `experiments/`; consequences: none.

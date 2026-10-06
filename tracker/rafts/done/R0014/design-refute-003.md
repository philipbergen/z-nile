# Answers to review 003 (R0014)

- F1: fixed: the `--jobs N is a cap` case accepts `1 passed, 2 failed` or `2 passed, 1 failed` (and requires a failed run); the uncapped runner (`3 passed`) and the hard-coded 2 (the `--jobs 3` half) are still killed. The review measured the original assertion failing a correct implementation in about 5-10% of runs, so it is loosened rather than made deterministic; consequences: none beyond the row text.
- F2: fixed: a row marked "code review" in Rules and mutants for the two mutants no spec sees (tests started before `par_wait`; wall clock started at the tests stage); the code reviewer is told to read the diff for them. No spec change, as the review suggested.

Three rounds are used. The last round's high finding is a one-line assertion loosening that the reviewer specified exactly; it was not re-reviewed.

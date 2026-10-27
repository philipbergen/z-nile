# Refute 003: c0154 (design mode)

- F1: fixed: `promoted_unchanged` captures `git diff`'s output and exit status first (`out=$(… 2>&1) || { echo "cannot compare with origin/main: $out"; return 1; }`), then filters the captured text; `experiments/ac5-probe.sh` (a scratch repository) shows no change green, a changed promoted spec red, and origin/main deleted red, and the round-002 form fails that last probe (Rules and mutants row, run); consequences: a check run with no fetched origin/main is now red with git's message, which is the intended reading ("cannot compare"), not a false green.

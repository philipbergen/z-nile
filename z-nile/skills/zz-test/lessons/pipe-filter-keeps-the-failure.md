---
title: A filtered command keeps its own failure: never `cmd | grep -v … || true`
when: both
tags: [check.sh, shell, failures]
check: In every `cmd | filter || true` (or a filter after a pipe), does a failure of `cmd` itself still turn the check red?
---
A pipe's status is the last command's, and `|| true` then hides even that: when the command before the filter fails (no ref, a bad pathspec), it prints nothing to stdout, the filter gets an empty input, and the check reads "nothing changed" — green on exactly the case it can't judge.

**Why:** c0154 design review 003 F1: AC5's `git diff … origin/main...HEAD … | grep -v … || true` was green with origin/main deleted (`fatal: bad revision` went to stderr). Probed in `experiments/ac5-probe.sh`: the old form passes "no change" with no origin/main.

**How to apply:** capture the command's output and status first (`out=$(cmd 2>&1) || { echo …; return 1; }`), then filter the captured text; add a case where the command itself fails.

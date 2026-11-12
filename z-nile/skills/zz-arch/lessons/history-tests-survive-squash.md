---
title: A "not on main" history test survives main taking the branch as a squash
when: both
tags: [git, squash, history, exemptions]
check: Does any rule decide by "a commit of branch X that main doesn't have"? What does it answer once main lands X, or anything X is built on, as a squash (whose commits never reach main)? Is there a spec case where main squashes the base? And where a commit is found by a search: does it read the same range as the rule that claims it is unique, match the subject line only, and pin nothing for zero or two matches?
---
A test of the form "this branch holds a commit of X that origin/main doesn't" assumes landing brings X's commits into main. A squash merge lands X's change as one new commit, so X's own commits stay off main for good, and every branch that holds them, including everything built on X, matches the test forever.

**Why:** c0115 design review 013 F1: c0115's freeze ignored any branch holding a commit of `origin/prep-c0115` or `origin/impl-c0115` not on main. Both were built on c0120, which main took as a squash, so the test matched every branch built on c0120: a rogue branch cut from `prep-c0120` that added a skill folder was ignored, and AC12 passed.

**How to apply:** identify a stack by something that stays true after a squash: an exact name, or a commit the stack must hold, recorded by sha or found by its subject. A commit found by a search is only as unique as the range searched: read the same range the uniqueness check reads (the branch's own commits, `origin/main..<branch>`), match the subject line only (never `--grep`, which also matches body lines and walks main's history), and refuse anything but exactly one match. Test it with a fixture that holds what the real branch holds below that commit (the squashed base's commits), with mutants that pin the oldest commit of the range, the tip, or the first of two matches, and one that brings the history test back (c0115 design review 014 F1, F2).

**Note (c0261 design review 010 F6):** a cutoff keyed on when a file landed must query the merge onto main (`git log --first-parent --diff-filter=A`), because `./zn done` lands `--no-ff` and the plain query returns the layer commit's date. Ask: which commit's date does the query return after a no-ff merge, and is there a case with a row between the two?

# Design refute 001

- F1: fixed: the promoted case keeps only the rule (`loops.problems` is empty for both files); "the list is unchanged" is a `check.sh`-only part of AC1 (`git diff --quiet <merge base> -- tests/lib/loops.luau`), with its mutant run red (E6); consequences: after the raft lands the merge base is the commit itself, so the line passes trivially on main, which is intended.
- F2: fixed: the lesson `zz-execute/run-the-loop-scan-after-adding-a-loop` is written in this prep, the Root cause cites its file, and `harvest.md` has the note entry; consequences: none.
- F3: fixed: E5 records the slow-tier half of the affected specs on the prototype and on main (92 passed, 4 failed on both); consequences: none.
- F4: fixed: the repeated-id case compares the child's whole trimmed output with the one line; consequences: none (rerun on the prototype).
- F5: fixed: the Design says the place of a repeated id's entries is not specified and why; consequences: none.
- F6: fixed: step 3 runs `--project z-nile --full` and says what a red that main also shows means, and what a red only on the branch means; consequences: none.

# Design refute 005: c0193 (answers to design-review-005; verdict approve, five low)

- F1: fixed: the `codify` line of the c0181-first branch names the mutant the meta case does kill (an entry's reason emptied, which fails the static lint), and says the sweep's own mutants SW1 to SW8 are killed by the sequestered `scanners.spec`, not by that case; consequences: none.
- F2: fixed: "There is no separate `tests/meta` file" now says the opposite and why; the meta spec is 34 lines; steps 1 and 5 give 33 entries for `main` and 35 with this raft's own `loops.luau` and `hostile.luau`; the `tree.spec` description names `boundcmd` as well as `raftcheck`.
- F3: fixed: the claim reads "every text without a line end reaches `writes()`'s loop", with the reason that nothing is lost (it reads one line at a time).
- F4: fixed: Implementation step 4 no longer writes the meta spec; step 5 does, after `scanners.luau` and in the same commit as the entries.
- F5: fixed: step 4 tells the executor to run the specs that execute the lint (`loops`, `problems`, `tree`) through `./zn run --time 60 --` (c0191's runner) while developing.

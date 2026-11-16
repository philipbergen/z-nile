# Idea review 001

## Findings

- F1: The two hang cases are not in the permanent suite. On origin/main they exist only in `z-nile/.tracker/issues/active/c0193/acceptance/finishes.spec.luau` (lines 194–227, the `spins` and `witspin` cases). That is c0193's acceptance spec, and the raft R0072, which is still active, has sequestered it. Nothing under `z-nile/tests` contains "did not finish within", and I found no record of these cases being moved to a slow tier. So the Problem sentence is false as written today. The non-goal also fences off the very file the first Solution bullet has to change. The idea should either say it acts on the promoted copies after R0072 lands, or admit that it edits R0072's sequestered file. As written, the problem and the fence can't both be true.

## Verdict

revise

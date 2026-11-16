# Idea review 001

## Findings

- F1: The failure numbers are out of date. I ran `z-nile/tests/acceptance/c0042/cli.spec.luau` on this checkout, which is at origin/main `f6d2ca616`. It fails at line 84 with `expected 103, got 104`, not `expected 102, got 103`. The counts on origin/main show why: the spec finds 36 rafts in `pickman/.tracker` and 67 in `z-nile/.tracker`, and the page also shows `arcade/.tracker/rafts/R0110`. The cause still holds, but the quoted numbers are now false and will change again with every raft that lands. Describe the failure in a way that stays true, such as "the page shows one more raft than the spec counts, R0110 in arcade's root", or drop the numbers.

## Verdict

revise

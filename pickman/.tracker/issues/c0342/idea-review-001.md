# Idea review 001

## Findings

- F1: The Solution and the first Non-goal say only "the whole-file digest" has to change, but c0177's pin checks more than a digest. Its case "no compare of the shipped config against the classic tables…" (`pickman/.tracker/issues/active/c0177/acceptance/narrowed.spec.luau:76`, which moves to `pickman/tests/acceptance/c0177/` when c0177 is done) requires `count(src, "if (Session.GAME_CONFIG :: any).ramp then")` to be exactly 1. Removing that guard, as the second Solution bullet requires, makes the count 0 and fails that case even after the digest is re-pinned. Line 71's count of `set.tuning, ramp)` (3) also fails if the spec switches to reading the set's ramp as `set.ramp`. So "confined to the spec and its digest pin" is false as written. The change also has to update or remove those counts in c0177's spec, and that spec needs an Overrides entry.

## Verdict

revise

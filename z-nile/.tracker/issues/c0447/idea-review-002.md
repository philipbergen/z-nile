# Idea review 002

## Findings

- F1: The Problem's count of 55 of 111 is wrong, and the rule built on it misses specs. Only 47 specs `require` an `@znile/engine/…` module directly. The other 8 in the count load `@tests/lib/engine`, which is a fixture-copy helper that loads no engine module. Meanwhile 12 specs that never name an engine module still load one through a helper: `tests/lib/seal`, `netfix`, `loops` and `fakecli` all `require` `@znile/engine`/`@znile/lib`. Some specs also load `@znile/lib` and `scripts/tracker` Luau directly. So "every spec that `require`s a module of that command is replaced" and "no remaining spec `require`s a module the switch deletes" can both be true while a switch still deletes a module that a spec loads through a helper. That breaks the promise that the gate passes with no spec broken. The count, the switch rule and the status command's count need to cover modules loaded through test helpers, and to say whether `z-nile/lib`'s and `scripts/tracker`'s Luau count as engine.

## Verdict

revise

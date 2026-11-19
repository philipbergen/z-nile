# Refute 001: R0101 (code mode)

- F1: fixed b97186c3a: c0176's Verification log now says 1/2 before the patch (AC1 red, AC2 green), from three runs at the base ff1678d0 in a clone under `$TMPDIR`, and says the first 0/2 in the worktree was not reproduced and is not relied on; consequences: a log line only, so no check or spec changes; layer 1 was finished again and layer 2 rebased onto it, and both members' checks were rerun on the new stack.
- F2: deferred c0342: the player case's loop and the three pieces of before-and-after scaffolding in `f0125/speeds.spec.luau` are one clean-up for after f0147, captured as c0342 (`depends_on: [f0147, c0177]`, #371); changing the file now would void c0177's sequestered digest, and f0147's validation and `ramp.spec` guard the player's bound meanwhile.

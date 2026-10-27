# Refute 001: R0059 (code mode)

- F1: fixed: an own spec, `pickman/tests/unit/plain/plain.spec.luau` (the sequestered plain.spec unchanged): negative infinity is refused with its reason, and `roundTrip` refuses it; two different strings differ at eps 1e9 with `value.name: blinky against inky`; equal strings match at eps 0. H1 and H11 (yours) killed by it; recorded as a deviation in c0153's Verification log. Consequences: none; the helper is unchanged.
- F2: fixed: the Verification log now says Phase 0's full gate was skipped and names its stand-in, Phase 3's full gate on the branch; #156's head differed from the base in 17 non-tracker files (`git diff --stat b763e110 1eadf5a5 -- . ':!*/.tracker/**'`). Consequences: none.

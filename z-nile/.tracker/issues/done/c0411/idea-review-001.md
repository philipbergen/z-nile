# Idea review 001

## Findings

- F1: Problem bullet 2 says the retired-rafts spec "is red for the same reason". Today that isn't true. The spec is red because metrics crashes on the `idea` and `idea-challenge` spend rows, which is d0406's cause (rows like these are in `portal/.tracker/issues/c0392/spend.d`). Metrics crashes before the "lists every raft once" case ever compares its lists. The hand list of two projects only becomes the reason once d0406 is fixed, which is how bullet 1 words it. Read as written, bullet 2 can't be checked against main without assuming d0406 is already fixed. Bullet 1 holds up: `z-nile/projects.toml` registers seven projects, metrics walks all of them through `store.roots()`, and arcade (R0110, R0121, R0126, R0127) and portal (R0117, R0122–R0124) have rafts that the hand list leaves out.

## Verdict

revise

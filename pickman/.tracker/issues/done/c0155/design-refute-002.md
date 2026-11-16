# c0155 design refute 002

- F1: fixed: the floor is now on distinct boxes (keyed on `safeX`, `safeY`, `safeW`, `safeH`, `margin`; today's 13 calls give 13 distinct boxes), not calls; failure messages say `call k`; the zz-test/seed-every-enumerated-case note says "distinct elements, not calls". consequences: a new Rules row and mutant M13 (every box built from the first sample), run in a fresh clone: base passes, M1–M13 killed on assertions.

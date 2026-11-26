# Refute 006: c0262 (answers to design-review-006)

- F1: fixed: after a `split` the worker's text, zz-execute 4a and the Design say that `./zn resolve` has already captured the new issue and the worker captures nothing; work.spec AC8 and docs.spec AC12 pin the new words. consequences: none.
- F2: fixed: the redo-design `why` names the decision it came from (`resolve split` or `resolve amend-design`), pinned in verdict.spec AC14; the AC14 Test plan line names split and the unquoted case; `finalread.where`'s code comment defers to c0248's design for the base rule; work.spec AC8 pins "unless no member is left to land".

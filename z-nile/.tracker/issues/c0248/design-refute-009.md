# Refute 009: c0248 (answers to design review 009, the last round)

- F1: fixed: AC4 now renames the committed review with `git mv` (staged) and `./zn commit` refuses it ("a review round is never deleted or renamed"), then moves it back. Rules row: the rename split, mutant `rename-old-path-dropped` (only the new path read), killed by that step. Consequences: none.
- F2: fixed: check.sh's AC4 label names the rule as it now is (a new file's stamp kept only when it is a commit's own, a committed stamp never changed, a committed round never deleted or renamed, a hand-deleted round back only as restored, the `Inputs:` rule). Consequences: none.

Round 009 is the cap: these two answers were run (`./zn check c0248` and the mutant, E11's record) but not reviewed by a tenth round; no finding of any round is refuted or left open.

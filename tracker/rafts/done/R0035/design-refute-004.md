# Refute 004: R0035 (answers to design-review-004)

- F1: fixed: f0100's `place.spec` BlastView case now also bans `player` (with `pose`, `Camera` and `BlastView.start`) in BlastView's code, comments stripped, so a beam drawn from `frame.player` fails it. It passes on the prototype. consequences: none; one assertion changed (a word added to an existing list).

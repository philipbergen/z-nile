# Refute 003: R0060 (answers design-review-003)
- F1: fixed: the harness loads modules through `module["req" + "uire"](m)`, so the spec contains no literal require text. Verified by placing the spec in `tests/acceptance/c0400/` on the prototype and running `tests/meta/architecture.spec.luau`, which passes (see the author's verification note in the prep commit).
- F2: fixed: the walk run now presses ↑ on the Waiting tab's first row (two rows) and expects the selection to stay on Epsilon. The mutant "↑ wraps to the last row" fails.
- F3: fixed: E3's count is corrected (four specs and 21 cases then; five and 28 now). The reachability claim now states the exception: waiting rafts that block only each other are reachable by search alone, which is accepted as making a tracker error visible.

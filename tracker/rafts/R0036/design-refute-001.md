# Design refute 001

- F1: fixed: `narrowed.spec` now pins the assertions themselves (`toBe(action)`, `toBe(nil)`, `Movement.isIntent(View.action(key))).toBe(true)`, the string-name check, `n >= 4`, the full unbound list including `""`) and forbids ` or true`; mutants M8 to M11 added and run, all fail on an assertion; consequences: none (the needles are tied to the exact narrowed text, which the patch fixes; a later edit to `keys.spec` must update `narrowed.spec`, as its header says).
- F2: fixed: c0103 has `raft: R0036`; consequences: R0035's issues (f0100 to f0102, f0104) have the same blank `raft:` and R0035's prep must set it (noted for that prep).
- F3: fixed: decided that `View.snap` stays (pinned by `f0014/look.spec`, AC4); only the snap-look key goes. c0103's Design says so under "What f0104 must leave alone", and f0104's Solution is reworded; consequences: f0104's springback may reuse `View.snap`, which is no new rule here.
- F4: fixed: f0104 now says it edits no promoted spec (Overrides: none) and must not edit `keys.spec` or `narrowed.spec`; consequences: none.
- F5: fixed: the Solution no longer promises a Controls check; consequences: none.
- F6: fixed: the "gone" needles are whole-token frontier patterns, with `Left`/`Right` checked in key position (`Left =` and `["Left"] =`); mutant M12 (`["Left"] = "Left"`) added and run, fails on an assertion; consequences: none.

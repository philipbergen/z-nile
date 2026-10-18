# Design refute 001: R0032
- F1: fixed: `plan.spec` checks the game target field by field (`expectGame`) and pins only `attributes.GamePlaceId == nil`, so f0065 can add its lobby-id attribute to the game target and pin it in its own spec; c0064 Design and R0032 Order say so. consequences: one new rule row (the game place is never told a `GamePlaceId`), with mutant M31 (game told `GamePlaceId = 1`) run and killed. No user decision: f0065 picks its own attribute name.
- F2: fixed: three new `runtime.spec` cases on a modified lobby build: a `Server` folder added, `CharacterAutoLoads = true`, `StartGame` removed. The Rules and mutants row is widened; mutants M27-M29 run and killed on assertions. consequences: none.
- F3: fixed: `deploy.spec` asserts `published before the failure: version=41`; mutant M30 (the line dropped) run and killed. consequences: none.
- F4: fixed: the line now starts `Overrides:` and names both specs; the narrowing details follow it.

# Response to design-review-003 (final round; the user decides whether it's ready)

- F1: fixed: `graph.stripComments` is now a small lexer. String literals (`''`, `""`, backticks, `[[ ]]` / `[=[ ]=]`) are copied verbatim, `--[=*[` opens a block comment only outside strings, and `---[[ … --]]` toggles are line comments. New cases in tests/tooling/affected.spec.luau cover all three reproductions from the review, plus quote escapes and leveled block comments.
- F2: fixed: the ci-workflow spec forbids `continue-on-error` on the job and on every step, and forbids `|| true` in any step's run.
- F3: fixed: `withPromotedCopies` runs the check in `pcall`, always removes the untracked copies, and then re-raises.
- F4: fixed: the `tests/acceptance` exclusion applies only to the `done` commit (`stagedStats(isDone)`), so later edits to promoted specs count as spend. The tracker skill's Spend section documents this.
- F5: fixed: c0020's Design requires `place.requireSpecs` to call `graph.stripComments` before scanning.

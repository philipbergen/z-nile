# Review 003: R0041 (design mode)
Inputs: d8cf35e plus the uncommitted prep files: tracker/rafts/R0041/R0041.md, design-review-001/002.md, design-refute-001/002.md, tracker/issues/c0106/c0106.md, tracker/issues/c0106/check.sh, tracker/issues/c0106/acceptance/narrow-radar.spec.luau and narrow-adapter.spec.luau; read against tests/acceptance/d0105/{radar,adapter}.spec.luau, tracker/issues/f0029/f0029.md, scripts/check.sh.
Dropped from design-review-002: none. F1, F2 and F3 are fixed as design-refute-002 says.

What I ran (all scratch, under `.cache/review-scratch3`, now deleted):
- Cut the two Design snippets out of c0106.md literally (lines 46-59 and 65-74, pasted at column 0) into copies of the two d0105 specs, replacing the whole-table `toEqual` (radar) and the `block` string plus its assertion (adapter). Ran `stylua` on the copies, then `stylua --check`: clean. The diff against today's files is exactly the Design.
- Pointed copies of both narrow specs at those copies (only `DIR` changed) and ran them with the narrowed copies: **28 of 28 pass** (narrow-radar 7, narrow-adapter 10, narrowed radar.spec 7, narrowed adapter.spec 4, the last two on the real place). The recorded fingerprints `331565424:3322` and `732226448:2134` match.
- `bash tracker/issues/c0106/check.sh` on today's tree: AC1 fails with 3 cases, AC2 with 4 (the f0029 witnesses, the tail case, and all four fingerprint and id cases on the `assert` "no region starts with"). AC3 passes.
- `selene --quiet src tests scripts tracker`: 0 errors and 0 warnings. `stylua --check src tests scripts tracker`: clean. `luau-lsp analyze --platform=standard` on both narrow specs and both narrowed copies: clean, so the specs also pass the types stage once they are promoted into `tests/`.
- Mutants on the narrowed copies, each killed: `barHeight` dropped (2 cases fail), an early `return` when `l.safeX ~= nil` (2), `[^)]*%)` (2), the `^` anchor dropped (1), the Position line dropped from `tail` (1), the head without the `Connect` line (1, so the `reasoned` row holds), the `local view` count neutralised (the count case and both adapter fingerprint cases), `SIZE = 121` in another radar case (both radar fingerprint cases).
- f0029's `Hud.layout(width, height, inset?)` keeps its two-argument form, so after f0029 lands `narrow-radar`'s "accepts today's layout" (the real layout plus the safe fields) still passes. `narrow-adapter` uses only synthetic sources.

### F1 [low] Step 1 and E2 understate today's failures, and some of them are `assert` errors
Where: c0106.md Implementation steps 1 ("confirm AC1 and AC2 fail on assertions"); Unknowns E2 ("3 fail on assertions (plus the two fingerprint cases ...)").
Evidence: today 7 cases fail, not 5. The two fingerprint cases and the two id cases all stop on `fingerprint`'s Lua `assert` (`no region starts with ...`), not on a `t.expect`.
Critique: an executor who compares step 1 against the record sees four extra failures, two of them in id cases E2 doesn't mention. It may lose time deciding whether they fail "for the right reason".
Consequences: none.
Recommendation: in E2 and step 1, say that 7 cases fail today: 3 on `t.expect` (f0029's layout, f0029's line, the tail case), and the 2 fingerprint and 2 id cases on the missing region, which is the expected failure until the snippets are pasted.

### F2 [low] R0041 Risks still names the old single `narrow.spec`
Where: R0041.md, Risks & rollback.
Evidence: "`narrow.spec` guards it with mutants". F3 of review 001 split that file into `narrow-radar.spec` and `narrow-adapter.spec`.
Critique: a stale name in the raft document.
Consequences: none.
Recommendation: name the two specs, and add that the fingerprints also guard the other cases.

Verdict: approve

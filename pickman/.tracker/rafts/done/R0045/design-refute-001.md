# Response to design-review-001

- F1: fixed: new `golden.spec` pins each whole file by the sha256 of its normalised text (c0103's normalisation; comments kept), new AC4 "no other case changes: both files are exactly the narrowed ones", and the Regression guard now names it. Consequences: any later change to either promoted file must update the digest (said in the spec and the Design); mutants unnarrowed-case-loses-assert and comment-edit are killed.
- F2: fixed: the narrowed opens case now also requires `companion|HiscoreEntries|all` among the opens (in the patch, and probed by `guards.spec`); the budget rule for HiscoreTop updates is pinned by `golden.spec`. Rows and mutants top-skips-budget-check and opens-drop-entries-required. Consequences: the narrowed files still pass on `origin/main` and on R0044's prototype (44 cases on 83731666).
- F3: fixed: all three c0128 specs build the paths as `"tests/" .. "acceptance/" .. renamed.id("f0024")` (and f0026), as c0063 and c0103 do. Consequences: none.
- F4: fixed: the stores case requires exactly 6 opened stores, or 7 when `HiscoreTop|all` is one; probed by `guards.spec`, mutant stores-no-count.
- F5: fixed: the prep note now says the capture conflicts with itself (Solution bullet 3's clause against the Outcome), that the Outcome wins and why, and that the bullet stays as captured.

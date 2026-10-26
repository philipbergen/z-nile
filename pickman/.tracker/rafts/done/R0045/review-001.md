# Review 001: R0045 (code mode)
Inputs: branch R0045-narrow-hiscore-adapter-pins at a0a14abc, `git diff origin/main...HEAD` (merge base d24aabc8, origin/main a0ac545e), R0045.md, c0128.md, R0045 and c0128 `check.sh`, c0128 `acceptance/{titles,guards,golden}.spec.luau`, `experiments/narrowing.patch`.

What I ran:
- `./zn check c0128` in the worktree: 4/4.
- `z-nile/check.sh --full` in the worktree: pickman 1404 passed, 0 failed; z-nile 1222 passed, 0 failed; `GATE PASSED (full)`, 738.2 s.
- Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` printed nothing, and `git diff --summary` shows no mode change.
- Fidelity to the reviewed patch: in a scratch clone at the merge base d24aabc8, `git apply --directory=pickman .../experiments/narrowing.patch` produced the blobs `4dcd3dd8` (f0024) and `f77fe1a5` (f0026). These are byte-identical to HEAD's. The base blobs are still `aa100297` and `21647d7e` (Implementation step 1), and `experiments/` is unchanged since the ready. The delivered narrowing is therefore exactly the one design review 002 passed, and AC4's digests are digests of that text. They are honest in that sense, but F1 shows how much they actually pin.

Narrowing, rule by rule (keeps every per-player rule and allows only what d0124 needs):
- The stores case had an exact six-element list. It is now all six required, every name in the six or `HiscoreTop|all`, and a count of 6 or 7. That keeps the old rules ("no other store", "no store under two kinds"). It adds only `HiscoreTop|all`, which is what d0124 needs.
- The budgets case still requires both budgets of the update's own kind before every update, HiscoreTop's included. Exactly six non-HiscoreTop updates are still counted. The prefix test for the kind is equivalent to the old equality.
- The three answer cases: `four()` maps every answer, so the number of answers is still compared, and so are the first four values of each. Day answers in the other cases still compare all five values.
- The opens case still allows only the two companion names, and still requires `companion|HiscoreEntries|all` and at least one open of each kind.
- The page-of-50 case: row reads (keys 101..130) must be more than 0 and at most N. Only reads of other keys are no longer bounded, and d0124's own specs pin those.
No `src/` change. The stubs are in memory. There is no repository-safety path.

### F1 [high] AC4's whole-file pin (and AC3's text probes) pass when an assertion is deleted by joining it onto the comment line above it
Where: `pickman/.tracker/issues/active/c0128/acceptance/golden.spec.luau:19-26` (`normalised`: `string.gsub(text, "%s+", " ")`); AC4 and AC3 in `c0128/check.sh`
Evidence: in the scratch clone at a0a14abc I edited `pickman/tests/acceptance/f0026/adapters.spec.luau` in two places. Each edit replaces a newline with a space:
```
-			-- reads at 0, 2 and 6 s (failure waits of 2, 4, then 8 s), each at page sizes 10 and 50
-			t.expect(#w.reads).toBe(6)
+			-- reads at 0, 2 and 6 s (failure waits of 2, 4, then 8 s), each at page sizes 10 and 50 t.expect(#w.reads).toBe(6)
-			-- c0128: the per-player companion store is still read
-			t.expect(table.find(w.opens, "companion|HiscoreEntries|all") ~= nil).toBe(true)
+			-- c0128: the per-player companion store is still read t.expect(table.find(w.opens, "companion|HiscoreEntries|all") ~= nil).toBe(true)
```
`./zn check c0128` in the clone then printed `PASS AC1`, `PASS AC2`, `PASS AC3`, `PASS AC4` (4/4). Both assertions are now comments.
- The first sits in an unnarrowed case. That is exactly the "assertion deleted from an untouched case" mutant that design review 001 F1 introduced `golden.spec` to kill.
- The second is the required HiscoreEntries open from design review 001 F2. `guards.spec` probes it as text, and the text is still there, inside the comment.

The same clone run is not a false pass: changing the swallowed `toBe(6)` to `toBe(7)` turned AC4 red (`expected "f5a74905…", got "c0000f50…"`).

`golden.spec`'s header claims "comments are kept, so no code can hide in one". Collapsing `\n` into the same token as a space breaks exactly that claim, because a Luau line comment ends at the newline. The same normalisation search shows it was copied from c0103:
`git grep -nF '"%s+", " "' -- '*.luau'` → `c0128/acceptance/golden.spec.luau:21`, `pickman/tests/acceptance/c0103/narrowed.spec.luau:23` (both whole-file pins of a Luau spec). The other hits (`c0015/workflow`, `c0053` replacement, `c0001/ci-workflow`, `c0060/retrofit`, `c0076/sweeper`) normalise text for probes, not for whole-file pins.
The f0024 file is exposed the same way at its two `-- c0128:` comment lines above the narrowed guards. A spot check of c0103's target (`f0014/keys.spec.luau`) found comments only in its header, above `local` lines, so it is far less exposed there. That part was read, not run.

Critique: the delivered code is right. I proved byte-identity with the reviewed patch above. But AC4 is the criterion that pins "No other case changes". Per the severity rubric, an AC that a wrong implementation passes is high, and `golden.spec` is promoted as the long-term guard of both files. After `done`, any later edit can delete an assertion this way and stay green. The fix the author will be tempted to make is to edit `normalised` in the sequestered `golden.spec`. Code mode forbids that.
Consequences: any fixed normalisation has to keep a line comment's end. Options: collapse horizontal whitespace only and keep one `\n` per line break, or end each `--[^\n]*` with a marker before collapsing. That changes both digests, so this is a re-prep of c0128's sequestered spec. c0103's promoted `narrowed.spec` uses the same normalisation, and the lesson `zz-test/narrowing-pins-the-whole-file` recommends it as written. The fix belongs there too, or the next narrowing copies the hole. A new mutant row ("join an assertion onto the comment above it") is needed in `mutants.py` for both.
Recommendation: escalate to the user (zz-execute stop conditions). The author cannot fix this without editing sequestered files. Options:
- (a) Re-prep c0128's `golden.spec` with a newline-preserving normalisation, recompute both digests, and add the comment-join mutant to `experiments/mutants.py`. Cost: a prep round, and R0044 stays blocked until it lands.
- (b) Accept AC4 for this PR on the reviewer's byte-identity proof (HEAD blobs `4dcd3dd8`/`f77fe1a5` = `narrowing.patch` applied to `aa100297`/`21647d7e`). Then capture a chore that fixes the normalisation in both promoted pins, c0128's `golden` (after promotion) and c0103's `narrowed`, recomputes their digests or texts, and updates the lesson. Cost: the hole stays open on `main` until that chore lands.
Either way the lesson needs the amendment below.
Lesson: zz-test/narrowing-pins-the-whole-file

## Judged criteria (code mode only)
- c0128 has no Judged criteria (`### Judged: None`), so there is nothing to rule on. R0045 has none either.

Candidate lesson (for the lead to harvest; a reviewer writes no lesson file): amend zz-test/narrowing-pins-the-whole-file. A whole-file normalisation of code must keep line breaks wherever the language ends something at a newline (Luau `--` comments). Otherwise a deleted assertion hides as the tail of the comment above it, and the text probes still find it. Check: does the normalisation map `"-- x\nassert()"` and `"-- x assert()"` to different texts, and does the mutant set include "join a line onto the comment above it"?

Verdict: changes

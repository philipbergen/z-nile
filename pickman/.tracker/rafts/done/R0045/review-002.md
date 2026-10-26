# Review 002: R0045 (code mode)
Inputs: branch R0045-narrow-hiscore-adapter-pins at c40d497d (origin/main 1e749844, merge base 3bf887d6), `git diff origin/main...HEAD`, the fix delta `git diff f3093bb0..c40d497d` (f3093bb0 added review-001; the fix commits are 2c0dd969 and c40d497d), review-001.md, refute-001.md, R0045.md, c0128.md, c0128 `check.sh` and `acceptance/golden.spec.luau`, c0156 on origin/main.
Dropped from review-001: none (F1 is fixed, see below)

## Ruling on review-001 F1
Fixed, and the fix is right. The user decided (2026-10-25) "Fix the pin now", which authorised this one edit to c0128's sequestered `golden.spec`. c0128.md records that as a `Decided with the user (2026-10-25)` line. Because of that decision, the sequestration listing's one non-R100 line (`M pickman/.tracker/issues/active/c0128/acceptance/golden.spec.luau`) is not a finding. Nothing else under `**/acceptance/**` or `**/check.sh` changed.

What I ran (worktree, and a scratch clone at c40d497d):
- `./zn check c0128` in the worktree: 4/4. `./zn promote-check R0045`: OK. selene on golden.spec: 0 errors. `stylua --check`: clean.
- Digests belong to the reviewed narrowing. I re-ran review-001's proof. In a clone at d24aabc8 (the base blobs are `aa100297`/`21647d7e`), `git apply --directory=pickman experiments/narrowing.patch` gives `4dcd3dd8`/`f77fe1a5`. HEAD's f0024 and f0026 blobs are exactly those (`git rev-parse HEAD:<path>`). golden.spec passes at HEAD, so `7f791c55…`/`744eeb0f…` are the new `normalise` applied to the reviewed narrowing. Neither narrowed file changed since review 001.
- Review-001's evidence, re-run: joining the "reads at 0, 2 and 6 s" comment and the next line with a space now fails `f0026 adapters is exactly the narrowed file` (and the join case), while AC1 stays 25/25. That is the mutant, now killed.

The normalisation holes I tried. Each one was run in the clone on f0026's adapters spec (golden result / AC1 result):
| mutant | golden | Luau semantics |
|---|---|---|
| comment and next line joined with a space | red | assertion becomes a comment |
| joined with `\v` or `\f` (Luau's lexer runs a `--` comment through both; probe: `n=0`) | red | assertion becomes a comment |
| joined with a lone `\r` (Luau ends a comment at `\r`; probe: `n=1`) | red (indent differs). The same text with the indent kept would be green, but it is semantically the same code, so that is not a hole | unchanged |
| `--[[ … ]]` wrapped around the assertion | red | assertion removed |
| `-- ` put in front of the assertion | red | assertion removed |
| `toBe(6)` → `toBe(7)` | red | changed |
| whole file re-indented (tabs → spaces) | green | unchanged (correct) |
| whole file CRLF | red on the join case only (see F1) | unchanged |

The rest of the equivalences, reasoned and then checked against the two files:
- Trailing comma before `}`, across at most one newline: in Luau that comma is always a trailing table separator, unless it sits inside a string or a comment. `grep -nE ',[ \t]*\}'` finds none on one line in either file.
- Runs of spaces or tabs inside a string: `grep -nE '"[^"]*(  |\t)[^"]*"'` finds none, and there are no `[[` long strings.
- The id mask `%f[%w_][fdcR]%d+%f[^%w_]`: its only hits are item ids (c0128, d0124, f0024, f0026, f0061, f0065), and they sit in comments and titles. No variable such as `d1` exists.

A wrong implementation can't use any of these to change what either file asserts.

### F1 [low] golden.spec's `joined()` case undoes the LF normalisation the fix introduced: a CRLF checkout of f0026 fails AC4 falsely
Where: `pickman/.tracker/issues/active/c0128/acceptance/golden.spec.luau` `joined` (`string.find(src, comment .. "\n", 1, true)` on the raw file)
Evidence: in the scratch clone I rewrote `tests/acceptance/f0026/adapters.spec.luau` with CRLF endings and changed nothing else. golden.spec then printed `FAIL … the review's two joins in f0026 adapters each change its digest`, 3 passed and 1 failed, while both digest cases passed (normalise maps `\r\n` to `\n`). The header says line endings are made LF so that the pin is independent of them, and this case is not.
Critique: there is no `.gitattributes` and CI is `ubuntu-latest`, so this only bites a checkout with `core.autocrlf=true`. It is a false red, not a false green. The file is sequestered, so the author can't fix it here.
Consequences: a fix normalises `src` to LF before searching, which is `normalise`'s own first steps. That adds no new rule.
Recommendation: no change in this PR. Add a line to c0156, which already owns "one shared normaliser" for both pins, saying the join helper reads the text through the same LF step.

### F2 [low] Three records still say F1 was deferred to c0156, which the user's later decision replaced
Where: `pickman/.tracker/rafts/active/R0045/R0045.md` "Addressed during execution" ("None fixed here. Captured: c0156 … deferred by the user's decision (2026-10-25) "Merge, chore the hole""); `z-nile/skills/zz-test/lessons/narrowing-pins-the-whole-file.md` last paragraph ("Fixed by c0156"); c0156 on origin/main (Problem: "R0045 (c0128) lands, and this chore closes the hole"; Solution overrides "c0128's promoted `golden.spec`"; Non-goals say "The narrowing itself (c0128, done)").
Evidence: refute-001 says "c0156 now covers only c0103's pin and the lesson". But `git diff origin/main HEAD -- z-nile/.tracker/issues/c0156` is empty, so nothing records that.
Critique: a later prep of c0156 will re-design a fix for a pin that is already fixed, and the lesson points readers at the wrong fix. The author's tempting fix is to rewrite c0156's Problem so that it covers only c0103. That changes a capture's wording.
Consequences: c0156's scope is the user's. Its c0128 half is now delivered here, by the user's own decision, so it isn't being cut: it is done elsewhere.
Recommendation: in Phase 5 step 1, rewrite R0045.md's "Addressed during execution" to "Fixed here: review-001 F1, by the user's decision (2026-10-25) "Fix the pin now"". Fix the lesson's last sentence to "Fixed in c0128's golden.spec by R0045; c0103's by c0156". Add a `Decided with the user (2026-10-25)` line to c0156 that records c0128's pin as done in R0045, and leave its Problem text as it is.

## Judged criteria (code mode only)
- c0128 and R0045 have no Judged criteria, so there is nothing to rule on.

Candidate lesson (for the lead to harvest): amend zz-test/narrowing-pins-the-whole-file. Every helper in a pin spec that reads the pinned file (a search, a mutant builder) reads it through the same normaliser as the digest. Otherwise the pin's independence from line endings and indentation holds for the digest but not for the spec. Check: does each raw `fs.readFile` of the pinned file in the spec feed `normalise` before any search?

Verdict: approve

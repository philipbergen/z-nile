# Review 001: R0127 (code mode)
Inputs: layer R0127/1/f0395 at c5c56cc669ad8b842503e8dc11de46287bf0a07f, `git diff origin/main...HEAD` (merge base 45acddba6; `./zn sync --fetch` only, origin/main now 48f0e43e3), f0395.md, f0395's check.sh and acceptance/ (lines, client, docs specs), experiments/mutants.py, R0127.md and its check.sh.

Checks run by the reviewer:
- `z-nile/check.sh --affected`: exit 0; arcade 148 passed, 0 failed, 11 spec files (f0395's three sequestered specs, f0201's six promoted specs, `tests/place/wallet-order`, `tests/unit/PaidPlay`); format, selene and both type passes clean.
- `./zn check f0395`: 5/5 PASS.
- Dependents' places, run by hand because `lune run z-nile/affected` over the three source files selects no other home's place spec (no home's `tests/place/*.watch.txt` names a path under `arcade/src`, though every place maps it): portal and snake `tests/place/library.spec.luau` 2 passed each, pickman `tests/place/{library,structure,resolver}.spec.luau` 8 passed.
- Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` lists only `A arcade/.tracker/issues/active/f0395/acceptance/watch.txt`, which `./zn finish` writes, and which names exactly the layer's three source files (lesson zz-review/finish-watch-is-generated). No spec and no check.sh changed.
- JC1: `git diff --name-only origin/main...HEAD -- arcade/src '*/src'` lists exactly `arcade/src/shared/Logic/PaidPlay/init.luau`, `arcade/src/shared/Prices.luau`, `arcade/src/shared/TestPurchase.luau`.
- JC2 mutants, run by the reviewer against `arcade/tests/unit/PaidPlay/paidplay.spec.luau` (a scratch script under `./zn run --time 600`, swapping the one expression `experiments/mutants.py` names in `init.luau`, running the unit spec alone, restoring the file byte for byte; the tree was clean afterwards): Y1 (play line unstruck) killed by "testLines strikes a play's struck price…" and the escape case (21 passed, 2 failed); Y5 (`prices.price` for a revive) killed by "testLines gives a revive its own price…" and the escape case (21/2); Y7 (`plain` returns its text) killed by "testLines escapes every &, < and > in every text" (22/1).

What I attacked and found sound:
- `plain`: `&` is replaced first, every occurrence (no `n` limit), the outer parentheses drop gsub's count, and `&` in a Lua replacement string is literal (only `%` is special). Every text in a line passes through it once; the only markup is the play's `<s>…</s>`. With today's words it changes nothing, so the title and note lines are f0201's.
- Callers: the only production caller is `Receipts.ask` (`PaidPlay.testLines(t.entry.title, kind, Prices)`), which passes the frozen library table, now with `revive`; the strict type passes accept it. The f0201 promoted cases c0397 narrowed stay green. c0202's prepared specs use the library's `Prices` and compare through `testLines`.
- `TestPurchase`: `RichText` is set in the one line loop for every `Line{i}`; BUY and CANCEL are untouched; the client neither escapes nor strips. Authority is unchanged: the server builds every line.
- Architecture: PaidPlay stays a leaf with no engine word; no new require or deps edge; the two `architecture.md` sentences match the Design's §4 word for word.
- Performance: three `gsub`s over a few short strings per screen opened; nothing per frame.
- Repository safety and bounded commands: the diff adds no script, check.sh or helper; the executor's mutant runs are recorded as run under `./zn run`.
- Design adherence: steps 2 to 6 as designed, E6 recorded with its result, no deviation; the revive line stays the recorded Guess (pending the user), unchanged in scope.

### F1 [low] The unit escape case's comment says every text repeats each special character, but two of its texts do not
Where: arcade/tests/unit/PaidPlay/paidplay.spec.luau, case "testLines escapes every &, < and > in every text" (the `odd` table and the comment above it)
Evidence: the comment reads "each character at least twice in each text, so an escaper that replaces only the first one fails", but `struck = "<<9>>"` holds no `&` and `price = "&&2"` holds no `<` or `>`; only the title, `sale` and `revive` hold all three. The rules are still pinned: `plain` is one shared function, so a first-occurrence-only escaper (Y13) or a wrong order (Y8) fails on the title line, and the sequestered `lines.spec` (whose `struck` is "<<5 && 6>>") holds every field. So no plausible mutant survives today; the defect is a comment that overstates the case's inputs, and a later per-field escaper (for example escaping `struck` inside the tag differently) would be covered by less than the comment promises.
Critique: a reader trusting the comment would not add the missing characters if the escaping is ever split per field. The tempting fix is to delete the comment.
Consequences: deleting the comment loses the reason the inputs repeat characters (the lesson's point). Changing the inputs changes two expected strings in the same case and nothing else; no promoted or sequestered spec is involved.
Recommendation: make the inputs match the comment: give `struck` and `price` all three characters twice, side by side (for example `struck = "<<9&&>>"`, `price = "&&<<2>>"`), and update the case's two expected play lines; keep the comment. Rerun the unit spec and Y7 against it.
Lesson: zz-test/escaping-cases-repeat-every-character

## Judged criteria (code mode only)
- JC1: pass. `git diff --name-only origin/main...HEAD -- arcade/src '*/src'` lists exactly the three library files and nothing under another home's `src/`; the other changed paths are `arcade/.tracker/architecture.md`, `arcade/tests/unit/PaidPlay/paidplay.spec.luau` and f0395's/R0127's own tracker files, which the rubric allows.
- JC2: pass. The unit spec has the three cases the Test plan names ("testLines strikes a play's struck price, then the price and the sale", "testLines gives a revive its own price, nothing struck", "testLines escapes every &, < and > in every text"); no case expects a plain price line (f0201's "9 X 2 X DEAL" case is replaced, and no "5 R$ 1 R$ SALE" remains); and I ran Y1, Y5 and Y7 against the unit spec myself: each is killed by its row's case (results above). F1 is a comment-accuracy issue, not a missing case or a surviving mutant.

Verdict: approve

# Review 003: c0154 (design mode)
Inputs: prep-gate-slow 69e9c201 (c0154.md, check.sh, acceptance/{schedule.spec,durations}.luau, experiments/{schedule.luau,run.patch}, harvest.md, the new zz-test lesson unchanged-checks-start-non-canonical); design-review-002 and design-refute-002. The prototype (run.patch applied, schedule.luau as `z-nile/tests/lib/schedule.luau`, the spec promoted to `tests/acceptance/c0154`) is built in a scratch clone of 69e9c201 (reviewer's scratch `dr-r3b/c54`, its remote set to `/nonexistent`). `./zn lessons --when design`.
Dropped from design-review-002: F1, F2, F3, F4, F5, F6 (rulings below).

Rulings on refute 002:
- **F1 (check-paths rejects AC5's literal path): right.** On the c54 prototype, `lune run tests/run -- tests/acceptance/c0120/check-paths.spec.luau` gives `4 passed, 0 failed`. AC5 still catches a change through the absolute pathspec: after a committed edit to `z-nile/tests/acceptance/c0001/ci-workflow.spec.luau`, `bash check.sh` prints `FAIL AC5 … promoted specs changed: z-nile/tests/acceptance/c0001/ci-workflow.spec.luau`. `ZN_ROOT` is `pwd -P` (ac.sh:39), so no symlinked prefix confuses git. One new defect in AC5 is F1 below.
- **F2 (multi-return in t.expect): right.** Line 240 is wrapped. The recorded full gate's types stage has 0 errors. I didn't rerun promote-check.
- **F3 (full gate and Linux): right.** The Verification log records the per-project gate (pickman 1404, z-nile 1230) and the CI dispatch, run 40354630211, with both gates successful.
- **F4 (unchanged record from canonical bytes): right.** The fixture-only case starts from `"1\ttests/a.spec.luau\n"`. Spot-run: M19 (`if any then` → `if true then`, run.luau:233) fails `a run naming only a fixture's files leaves the record byte for byte`, 7 passed and 1 failed. The unmutated prototype passes schedule.spec 8/8. `parse("\n")` and `parse("\n\n")` are nil, asserted.
- **F5 (duplicate path): right.** `parse` refuses a second line for one path, asserted, and M18 is recorded as killed.
- **F6 (labels): right.** AC2's and AC4's labels quote the doc's current text.

### F1 [medium] AC5 passes when its `git diff` fails: the pipeline's status is grep's, and `|| true` swallows git's fatal error, so a missing or unresolvable `origin/main` reads as "no promoted spec changed"
Where: check.sh `promoted_unchanged`: `changed=$(git -C "$ZN_ROOT" diff --name-only origin/main...HEAD -- … | grep -v '^z-nile/tests/acceptance/c0154/' || true)`. ac.sh sets no `pipefail`.
Evidence: in the c54 clone I committed an edit to a promoted spec and ran `bash .tracker/issues/c0154/check.sh` from `z-nile/`:
- With `refs/remotes/origin/main` present: `FAIL AC5: no promoted spec changes`, `promoted specs changed: z-nile/tests/acceptance/c0001/ci-workflow.spec.luau`.
- After `git update-ref -d refs/remotes/origin/main` (the same edit still committed): `PASS AC5: no promoted spec changes`. git printed `fatal: bad revision 'origin/main...HEAD'` and exited 128, and nothing saw it.
The repo's other "unchanged" checks fail closed, because they call git directly (`git diff --quiet origin/main...HEAD -- …` in R0032, R0037 and c0114, from `git grep -n "origin/main\.\.\.HEAD" -- '*/check.sh'`). c0154's form, git piped into grep, is the one that fails open.
Critique: a sequestered criterion that passes because it read nothing is zz-test/no-vacuous-pass. A worktree with no origin/main ref (a fresh fixture, a single-branch clone, a renamed remote) would wave through an edited promoted spec. The tempting fix is `set -o pipefail` inside the function. That breaks the case it must allow, because grep exits 1 when it filters every line out, which is AC5's green.
Consequences: git's failure has to be told apart from grep's "no lines". Capture git's output and status first, then filter.
Recommendation: `local all; all=$(git -C "$ZN_ROOT" diff --name-only origin/main...HEAD -- "$ZN_ROOT/pickman/tests/acceptance" "$ZN_ROOT/z-nile/tests/acceptance") || { echo "cannot diff against origin/main"; return 1; }`, then `changed=$(printf '%s\n' "$all" | grep -v '^z-nile/tests/acceptance/c0154/' | grep -v '^$' || true)`. Record two runs in the Verification log: a clone with origin/main deleted gives FAIL, and the prep tree gives PASS. Keep check-paths.spec green (the paths stay `$ZN_ROOT`-prefixed). Also rerun `AC_LIST=1`.
Lesson: zz-test/no-vacuous-pass

Candidate lesson (for the lead to harvest; the reviewer writes none):
- zz-test: a check that filters a command's output (`cmd | grep -v … || true`) loses the command's failure. Capture the command's status before the filter, because `pipefail` would also fail the filter's legitimate "no lines". Check: if the first command in this pipeline exits non-zero with no output, does the check fail?

Verdict: changes

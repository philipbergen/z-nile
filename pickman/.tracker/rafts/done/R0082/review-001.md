# Review 001: R0082 (code mode)
Inputs: HEAD d0580155 (branch R0082-lobby-tooling-pattern), base and origin/main 2f0c11ff; `git diff origin/main...HEAD`; R0082.md and check.sh; c0237.md, check.sh, harvest.md; `./zn capture c0237` (capture 05bee6b8, confirmed, no marker).

No findings.

## Evidence run
- **Diff stays tracker-only.** `git diff --stat origin/main...HEAD` touches three files, all under `pickman/.tracker/`: c0237.md (Verification log only), c0237/spend.md (one build record, totals updated), R0082/spend.md (new rollup). `git diff --stat origin/main...HEAD -- . ':!*/.tracker/**'` is empty. The merge base is origin/main (2f0c11ff), so main hasn't moved since the branch was cut.
- **Sequestration.** `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` lists nothing. The move to `active/` landed on main before the branch was cut.
- **The fix is on main.** `git merge-base --is-ancestor 51968dcc origin/main` succeeds. `git show --stat 51968dcc` (#230) changes `pickman/tests/acceptance/f0061/lobby-tooling.spec.luau` by one line. Line 55 now reads `if string.match(line, '^%s*for f in "%${p}"%*%.project%.json; do') then`, and `grep -nF -e '%{' -e '%}'` on the spec finds nothing (exit 1).
- **`./zn check c0237`**: AC1, AC2 and AC3 PASS (3/3).
- **AC2 and AC3 are not vacuous.** I ran each AC's own `bash -c` body on scratch copies of the spec (outside the repo, in the session scratchpad):

  | copy | AC2 | AC3 |
  |---|---|---|
  | unchanged | pass | pass |
  | brace escaped back (`"%%{p%}"`) | fail | fail |
  | line 55 duplicated | pass | fail (count 2) |
  | line 55 deleted | pass | fail (count 0) |
  | spec file missing | fail (`[[ -f ]]`) | fail (empty count ≠ 1) |

  The inner double quotes in AC3 turn `\$` into a literal `$`, and `-F` matches it as a fixed string, so `${p}` is never expanded. A missing file gives an empty count rather than 0, and that still fails `== 1`.
- **`z-nile/check.sh --full`** (my run, at HEAD): GATE PASSED (full), gate wall time 223.3 s. It includes the `types (luau-lsp analyze, pickman/tests …)` stage, the stage the captured Problem says failed. The Stop hook (`scripts/hooks/stop.sh`) runs `scripts/check.sh --affected`, which is a subset of that gate, so it holds too.
- **Verification log is honest.** I reproduced every claim: there's no code or spec edit, 3/3 ACs pass, and the full gate passes. The log's gate ran on the base rather than HEAD. That's a valid stand-in, because the HEAD-vs-base diff outside `.tracker/` is empty (lesson zz-execute/check-a-stand-in-before-logging-it). My own run at HEAD agrees.
- **Captured scope is met.** The capture's only outcome is that luau-lsp stops rejecting `%{`/`%}` at line 55 and the type stage and stop hook pass on main. The escape is gone (AC2), the pattern is unchanged in meaning (AC3, AC1), and the type stage passes (full gate). The Solution's additions only add detail, and the 2026-11-04 change is covered by a `Decided with the user` line. Nothing was dropped.
- **Repository safety and bounded commands.** The diff adds no script, spec or check.sh. The sequestered check.sh's AC2 and AC3 are read-only greps, and AC1 goes through `tests/run`.
- **Lessons.** `./zn lessons --skill zz-review --full` and `./zn lessons --when build`: none is repeated. The diff removes no names (grep-preps-for-removed-names doesn't apply), there are no fix rounds, and the logged figure gives its command.

Verdict: approve

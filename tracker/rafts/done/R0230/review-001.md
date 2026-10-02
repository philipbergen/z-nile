# Review 001: R0230 (code mode)
Inputs: `git diff origin/main...HEAD` at 80b18e7 (commits 4c0596e, c19739f, 80b18e7); R0230.md, R0230/check.sh; c0530.md, c0530/check.sh, c0530/acceptance/setup-run.spec.luau; the deleted `tests/acceptance/c0460/setup-tools.spec.luau` (read from origin/main).

Checks run:
- Sequestration: `git diff 4c0596e -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` is empty.
- `scripts/check.sh --full`: GATE PASSED (757 passed, 0 failed, 120 spec files; wall time 31.2 s).
- `scripts/tracker.sh check c0530`: 9/9 PASS. `scripts/tracker.sh promote-check R0230`: OK.
- `git grep setup-tools` outside done history: only c0530's own document and check.sh. `tracker/issues/done/c0460/check.sh` no longer names it. `tests/acceptance/c0460/` still has board-docs and board-workflow.

Coverage audit of the deletion: I went through each assertion in the old slice spec and checked what replaces it.
- Cases 1-5 (gate with `--full`, `--tools` skips, CI/`PICKMAN_SKIP_GATE`/`GITHUB_ACTIONS` don't skip, red gate fails, unknown argument exits 2 and `--tools`/no argument are accepted): each one has a whole-run case in setup-run (cases 1, 2, 3/4, 5, 6), and those cases are stricter: exact exit code 3, both platforms, CI too, empty call log.
- Case 6 used text rules: one gate call, no other `set`, no `trap`, `exit` only in known places. Its behavioural intent is now covered by observing the run:
  - the gate is called once and last (case 1, mutant I);
  - `set +e` and deleted `set -euo pipefail` (D, E);
  - `trap "exit 0" EXIT` (L);
  - stray exits before the gate (N, A, B and the CI-variable mutants).
- I also checked some mutants not in E3 by reading:
  - `trap 'exit 0' ERR`: killed by case 5, which expects exit 3.
  - Backgrounding the gate (`scripts/check.sh --full &`): killed by case 5.
  - `exec scripts/check.sh --full`: killed by case 1 (no `SETUP OK`).
  - A skip on `[[ -t 0 ]]`: the spec's subprocess has no tty, so the gate doesn't run and case 1 fails.
- What's lost: text rules on non-gate shell options (for example `set -x`, `set +o pipefail`), and host-probe or CI-only-value bypasses. Neither can bypass the gate except through the gaps already recorded and accepted in R0230 Risks (design review 001 F2, design review 002 F2). Nothing beyond those gaps was lost.

The design calls for a deletion plus documents, and that is all the diff contains: no `setup.sh`, workflow or skill change. The verification log and the E4 result are recorded, and spend files are present. No architecture or performance surface.

No findings.

## Judged criteria (code mode only)
None.

Verdict: approve

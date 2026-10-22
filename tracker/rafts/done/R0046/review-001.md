# Review 001: R0046 (code mode)
Inputs: HEAD 417ae445 against origin/main 388078ad (merge base f22a6c4a; main gained only R0035's ready move, which touches no file this branch changes, and `git merge-tree` is clean); `git diff origin/main...HEAD` (src/server/Submits.luau, c0129.md verification log, spend files); R0046.md, R0046 check.sh, c0129.md, c0129 check.sh, c0129 acceptance `submits.spec.luau` and `onagain.spec.luau`.

Checks run by the reviewer:
- `scripts/check.sh --full`: GATE PASSED (full), 2037 passed, 0 failed, 298 spec files.
- `scripts/tracker.sh check c0129`: 3/3 criteria passed (AC1, AC2, AC3).
- `scripts/tracker.sh promote-check R0046`: OK.
- Sequestration (`git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'`): empty. No check.sh or acceptance file changed on this branch.

What I checked and found clean:
- Correctness: the diff deletes `Submits.again` and its comment, nothing else. `ready`, `step`, `pending`, `close`, `held`, `count` and `BindToClose` are byte-identical. No `again` hook in any form (`.again(`, `:again(`, `.again =`, `["again"]`) is left in `src/`. `Sessions` calls only `runs.ready` and `runs.step`, and `Main.server` passes Submits unchanged.
- Removed names (execute-raft/grep-preps-for-removed-names): `grep -rn 'Submits.again\|.again('` over `tracker/**/*.spec.luau` outside c0129 finds nothing, so no sequestered spec of another raft (R0035, just readied, included) pins the removed hook. `Hiscores.onAgain` is still referenced by `tests/unit/Hiscores/run.spec.luau` and f0025's `run.spec`, both green.
- Stale docs and comments: nothing in `src/`, `tracker/architecture.md`, `tracker/game-design.md` or the skills names `Submits.again`. `Hiscores.onAgain`'s own comment ("A play again that the session accepted…") is in Logic, which the Non-goals keep untouched.
- Design adherence: matches the Design exactly, no deviation, and no captured outcome is dropped ("remove Submits.again … keeping Hiscores.onAgain" is AC1 + AC2).
- Architecture, performance and server authority: a deletion in one adapter adds no edge, allocation or replication.
- Weak tests: AC1 runs the real Submits source on a stub engine whose `require` refuses unknown modules, and checks the exported set by equality. The scans strip comments and use patterns that spare `playAgain`. The prep's mutants M1–M4d are recorded as run. AC2 pins behaviour (run 1 → 2), not just existence.
- Repository safety: the diff touches no spec, check.sh, script or guard file (fence, hooks, ac.sh, repo-fence.spec).
- Lessons (`--when build` and the review skill's): none of them applies to this diff or is repeated by it.

## Judged criteria (code mode only)
None: c0129 has no Judged criteria.

Verdict: approve

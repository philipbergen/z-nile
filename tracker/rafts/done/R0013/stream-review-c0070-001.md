# Review 001: c0008 (stream mode)
Inputs: `git diff R0013-tracker-hardening...ws-c0008` (4 files: `scripts/tracker/main.luau`, tracker and execute-raft SKILL.md, `c0008.md`); `scripts/tracker.sh check c0008` run in the stream worktree: 3/3 criteria passed (AC1, AC2, AC3). `scripts/check.sh --full` was not run (time).

Scope: the diff touches only the Touched modules and the issue's own document (Verification log). No `check.sh`, acceptance spec or `tracker/architecture.md` changed.

Design adherence:
- `cmd.done`: `gh pr ready` in `pcall(sh.run, ...)`, rollback `git reset -q --hard HEAD` then `fail`, placed after the `if #promoted > 0` block and immediately before the member-move loop, so it runs whether or not anything was promoted. The old `sh.must("gh", {"pr","ready"})` after `recordAndCommit` is gone; `gh pr view` and `gh pr edit` remain after the push.
- Tracker skill: the `done` row and Merging step 3 carry the designed wording; step 3 no longer mentions the ready event as the trigger. Execute-raft Phase 5 step 3 matches.
- "Within a few minutes of the push": coherent. The poll keys on the final sha, the fallback `scripts/ci-verify.sh` needs a pushed HEAD, and the push is now the event that starts the run. The parenthetical about the `ready_for_review` run on the previous head is accurate.

No findings.

Verdict: approve

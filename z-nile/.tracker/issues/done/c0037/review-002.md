# Review 002: c0037 with c0036 and c0038 (code mode)
Inputs: 9195a08 (`git diff main...HEAD`); `.claude/skills/{tracker,execute-raft,review}/SKILL.md`; `tracker/issues/c0036`, `c0037`, `c0038` (docs and check.sh); `scripts/tracker/main.luau` (`reviewProblem`, `done`, `activeRaft`); `scripts/ci-verify.sh`; `.github/workflows/check.yml`; review-001.md and refute-001.md. I ran `c0036/check.sh` and `c0037/check.sh` (all pass); I did not rerun `scripts/check.sh --full` (skill prose only).
Dropped from review-001: none. F2, F3 (mostly), F5, F7 and F8 are resolved; F1, F4 and F6 are only partly resolved, and their remainders are repeated below as new ids.

### F1 [high] (repeat of review-001 F1) A contested high in round 3 still merges, and no human sees the "below the merge threshold" lines before the merge
Where: `execute-raft/SKILL.md` Phase 4 step 7; `tracker/SKILL.md` Merging step 1; `scripts/tracker/main.luau:410-440` (`reviewProblem`)
Evidence: The round-1 fix restricts the interim answer to medium and low findings, requires quoting in the PR comment, and files c0038. Two holes remain.
(a) "Unresolved high" has no referee. After round 3 no reviewer reads `refute-003.md`. The author can write `- F1: refuted: <argument>` against a round-3 high. `reviewProblem` accepts it, `done` passes, and Phase 6 merges. Nothing says a high that the author refutes instead of fixes counts as unresolved, and the author is the party who wants to merge. Rounds 1 and 2 are safe because a next round re-reads the refutation. Round 3 has no next round, so it is the only place the gate is decided by the author alone.
(b) The "quote every such line in the PR comment" audit is not an audit. Phase 5 to Phase 6 run back to back, and step 1 of Phase 6 merges as soon as CI is green. The human sees the quoted lines only after the merge. The tool still checks neither severity nor that the filed id exists, so the whole restriction is prose applied by the merging agent.
Fix: In Phase 4 step 7 and Merging step 1, define significant by the reviewer's own file. If `review-003.md` (or the latest round) contains any `[high]` finding or a `fail` Judged criterion that the author did not fix in a commit, stop with `BLOCKED:` regardless of what `refute-003.md` says. Only `fixed` answers clear a high. For the interim form, require `tracker.sh list backlog` to show the filed id, and say that c0038 is what makes it tool-enforced. Optionally have the agent post the round-3 comment and re-read it before merging. That is cheap, and it removes the impression of a human gate that does not exist.

### F2 [medium] Merging step 4's "fix on a finished PR" path cannot be run with the tracker after `done`
Where: `tracker/SKILL.md` Merging step 4; `execute-raft/SKILL.md` Phase 6 step 2 ("Post no further commits")
Evidence: After `done` the raft is in `done/`. `tracker.sh commit` calls `activeRaft()` (`main.luau:68-76`), which fails with "expected exactly one active raft on this branch", so the branch-up-to-date commits cannot use it and the spend row is lost. The "new clean review round (execute-raft Phase 4)" then writes `review-004.md` in a raft directory that `done` has already verified. Nothing re-runs `reviewProblem` on it, because `done` requires an active raft, so the new round is unenforced. Phase 4 also has a cap of 3 rounds, and the text does not say how a round 4 counts against it. The step is written as if the raft were still active.
Fix: State the mechanics. Either use plain `git commit` and `git push` for the merge commit and skip a new round when only tracker renumbering changed, or (for anything more) stop with `BLOCKED:` and leave it to the human. That is simpler and fails closed. Do not describe a re-review whose completion nothing checks.

### F3 [medium] Phase 6 removes the worktree before the final report is posted, so the report step runs from a deleted cwd
Where: `execute-raft/SKILL.md` Phase 6 steps 2 and 3; `tracker/SKILL.md` After merge step 2
Evidence: Step 2 removes the worktree (and ExitWorktree `remove` deletes the session's cwd). Step 3 then runs `gh pr comment <pr> --body-file -`. `gh` resolves the repo from the cwd and a git remote unless given `-R`, and a removed cwd makes later shell calls fail. This is the ordering that review-001 F4(b) and F5 warned about. The fix moved the report after the merge but left it after the cleanup as well. The report also needs the merge sha, which is best read before cleanup.
Fix: Swap the order: post the final report comment (with the merge sha from `gh pr view <pr> --json mergeCommit`) first, then clean up, with worktree removal as the last action. Or give `-R <owner>/<repo>` and run from `<root>`.

### F4 [medium] "Confirm the run's sha equals HEAD" and "every check pass" cannot be checked as written, and a stale skipped check satisfies the "non-empty list" test
Where: `tracker/SKILL.md` Merging step 3
Evidence: `gh pr checks` prints name, state and elapsed time but not the head sha, so the second bullet has no command. Also, `gate` was `skipping` (draft) on the earlier pushes of the same sha, so right after `done` the list is already non-empty with a `skipping` entry before the `ready_for_review` run registers. The "non-empty" poll passes at once, and `--watch --fail-fast` can exit 0 with nothing pending. The text says "every check `pass`", which should catch that, but it does not say to keep waiting while the only entry is `skipping`. An agent will likely read the exit 0 as green. Separately, `--fail-fast` is only supported on newer `gh` (2.83.2 has it), and the skill does not say what to do on an older one.
Fix: Replace bullets 1 and 2 with one check that can be run: `gh pr view <pr> --json headRefOid,statusCheckRollup`; require `headRefOid == $(git rev-parse HEAD)` and a `gate` entry with `status == COMPLETED`, `conclusion == SUCCESS`, and `event`/workflow run for `pull_request` (or the dispatched run). Treat `SKIPPED` as "not yet".

### F5 [low] `gh pr merge --squash` with the Co-Authored-By trailer has no command, and root `pull --ff-only` has no failure branch
Where: `tracker/SKILL.md` Merging paragraph and After merge step 1
Evidence: A `--squash` merge from a non-interactive agent needs `--body`/`--subject` to carry a trailer, or it uses the default message. "with the `Co-Authored-By` trailer" is not a command, so agents will differ. If the root is on `main` but dirty or diverged, `pull --ff-only` fails and only the "fetch refuses" case has a fallback.
Fix: Give one concrete command (`gh pr merge <pr> --squash --body "..."`) and a one-line fallback for a failing `pull --ff-only` (leave it, note it in the report).

### F6 [low] c0037 and c0038 docs are still `design: draft`; c0037's non-goal does not point at c0038
Where: `tracker/issues/c0037/c0037-auto-merge-when-verified.md` Non-goals; c0038 (`design: draft`, empty ACs, `check.sh` with no checks)
Evidence: The c0037 non-goal says "interim: refuted ... " but does not name c0038, so a reader of the doc cannot find the follow-up. c0038's `check.sh` has no `check` lines, so if started it would pass vacuously under `tracker.sh check`. `design: draft` blocks `start`, which is the intended guard, so this is only clarity.
Fix: Add "(follow-up: c0038)" to the c0037 non-goal, and leave c0038 as is until it is prepped.

## Judged criteria (code mode only)
None defined.

Verdict: changes

# Review 001: c0037 with c0036 (code mode)
Inputs: 314bba1 (`git diff main...HEAD`); `.claude/skills/{tracker,execute-raft,review}/SKILL.md`; `tracker/issues/c0036`, `c0037` (docs and check.sh); `scripts/tracker/main.luau` (`reviewProblem`, `done`); `scripts/ci-verify.sh`; `.github/workflows/check.yml`; `gh api .../branches/main/protection`.
Not run: `scripts/check.sh --full` and the two issue `check.sh` files (this change is skill prose only, and I did not rerun the gate).

### F1 [high] The "below the merge threshold" answer lets any finding, including a high, through `tracker.sh done`, and nothing verifies the filed issue
Where: `execute-raft/SKILL.md` Phase 4 step 7; `scripts/tracker/main.luau:431-432` (`reviewProblem`)
Evidence: `reviewProblem` accepts any line that starts with `fixed` or `refuted`, so `- F1: refuted: below the merge threshold, filed as c9999` clears an unresolved high or a failed-Judged round. The tool does not check the round number, the finding's severity, or that `c9999` exists. The "only medium and low" rule exists only as prose that the same agent who wants to merge is trusted to apply. The design gives the author unilateral authority to downgrade the reviewer's finding and then merge with no human in the loop, which is the very authority the old "agents never merge" rule withheld. It also contradicts step 4 of the same phase ("Only refute when you can show the reviewer is wrong"), because this form is a `refuted` that is not a refutation. The Non-goals section of c0037 says it is deliberately interim, but the interim is the merge gate and is not marked as such anywhere in the skills.
Fix: minimum, in the skill, restrict the form to a medium or low finding of the reviewer's own labelling, require a real existing issue id (verify with `tracker.sh list backlog`), and require the round-3 PR comment to quote each such line so a human can audit it. The proper fix is a `deferred <id>` answer in `reviewProblem` that rejects it for high findings and unknown ids. If that is out of scope, file it now as a follow-up and link it in c0037 so the interim does not become permanent.

### F2 [medium] Merge safety rests entirely on agent discipline; the repo has no branch protection or required checks
Where: `tracker/SKILL.md` "Merging" (steps 3, 4 and "Never bypass branch protection")
Evidence: `gh api repos/:owner/:repo/branches/main/protection` returns 404 "Branch not protected". "Never use `--admin`, never bypass branch protection" is therefore vacuous: `gh pr merge --squash` succeeds on a red or missing check run, a draft-skipped CI, or a `BEHIND` or `UNSTABLE` state. `mergeStateStatus` is named but the acceptable values are not. Only `CLEAN` is safe. `UNSTABLE` means a failing non-required check and `BEHIND` cannot merge if protection is on later. Nothing in the flow fails closed if the agent misreads the output.
Fix: state the exact pass condition (`mergeStateStatus == "CLEAN"`, `mergeable == "MERGEABLE"`, PR `isDraft == false`). Add a chore issue to turn on branch protection with the `gate` job required, and say in the skill that until then the conditions are advisory and fail-open.

### F3 [medium] CI-on-the-head-sha condition mixes two different kinds of run and leaves the dispatch path underspecified
Where: `tracker/SKILL.md` Merging step 3; `.github/workflows/check.yml`; `scripts/ci-verify.sh`
Evidence: `gate` runs for `pull_request` only when not draft, and `done` marks the PR ready after pushing. So the `ready_for_review` event starts a PR run on the same sha (fine), but the text says "If CI never started ... dispatch". The two cases produce runs of different event types. `gh pr checks` reports the PR's head-sha check rollup and can be empty right after `gh pr ready` before the run registers, so `--watch` can exit immediately with "no checks reported" (nonzero, or zero with nothing watched depending on gh version), which an agent may read as green. The dispatch run also executes the sequestered-spec step, which finds nothing after `done` moved the raft out of `active/`, so it proves nothing extra. Separately, `ci-verify.sh` dies if HEAD differs from `origin/<branch>`, which is exactly the state after the step 4 merge-of-main until you push.
Fix: say to confirm the check list is non-empty and each entry is `pass` for `headRefOid` (`gh pr view --json headRefOid,statusCheckRollup`), and after the step 4 merge to push first, then re-run 2 and 3. Note that `ci-verify.sh` is needed only if the PR run is absent.

### F4 [medium] After-merge cleanup steps cannot run as written for a real agent session
Where: `tracker/SKILL.md` "After merge" steps 1-2; `execute-raft/SKILL.md` Phase 6 step 2
Evidence: (a) `git worktree list --porcelain` shows this very worktree as `locked claude session skills-post-merge-cleanup (pid ...)`. `git worktree remove <path>` refuses a locked worktree (it needs `--force --force`, or `unlock`), and the text only allows one `--force`, only for ignored leftovers. (b) "If your session is inside it, leave it first": the agent's shell cwd resets each call and the harness owns the session cwd, so the agent cannot leave. Removing the directory kills later commands, including the "merge commit sha in the final report" and `git worktree prune`, unless they run from an absolute path in the root. (c) `<root>` is never defined or discoverable from the text. The way to find it is `git worktree list | head -1` (the first entry is the main worktree). (d) `git fetch origin main:main` refuses if `main` is checked out in any other worktree, not only the root, and the "root on another branch" case does not say what to do if that fetch fails. (e) Step 3's `git branch -D` is explicitly gated on the confirmation, but the confirmation command is only `gh pr view --json state`, with no expected value (`MERGED`).
Fix: define `root=$(git worktree list --porcelain | sed -n '1s/^worktree //p')`; run every step as `git -C "$root" ...` with absolute paths; add `git worktree unlock <path>` before `remove` for harness-locked worktrees; require `state == MERGED` and `git -C "$root" ...` for `branch -D`; and say that removing the session's own cwd is done last, so the final report and PR comment come first. If the fetch fails, leave `main` alone and note it in the report.

### F5 [medium] Ordering contradiction: the final report and PR comment come before the merge
Where: `execute-raft/SKILL.md` Phase 5 step 3 vs Phase 6 step 3
Evidence: Phase 5 writes the final report "as a PR comment", then Phase 6 merges and says "put the merge commit sha in the final report". The PR comment never carries the sha, and the Phase 5 step is copied verbatim into the PR before any BLOCKED outcome from Phase 6 is known. If the merge is then blocked, the PR carries a "done" report for an unmerged PR.
Fix: move "write the final report" to the end of Phase 6 (after the merge and before removing the worktree), or add one short "Merged as <sha>" comment.

### F6 [medium] Step 4 (behind or conflicting) re-opens the whole flow after `done`, with no guidance on the tracker state
Where: `tracker/SKILL.md` Merging step 4
Evidence: after `done` the items are in `done/`. Merging `origin/main` and "renumber any colliding IDs (see Conflicts)" edits a finished raft, which makes a new commit on a ready PR that the reviewer never saw (no review round covers it). The step only says to repeat 2-3, not to re-check condition 1 or that the renumber left `tracker.sh check` green. A conflict resolution in skill or source files is unreviewed code merged autonomously.
Fix: after merging main, rerun `tracker.sh check` for the raft, and if the merge touched anything beyond tracker-ID renumbering, treat it as a `BLOCKED:` stop or a re-review instead of merging.

### F7 [low] c0036 still states a non-goal that c0037 contradicts, and both are left `design: draft` with empty template sections
Where: `tracker/issues/c0036/c0036-post-merge-cleanup.md` Non-goals ("agents still merge only when the human asks"); both issue docs (`design: draft`, empty Solution and Design)
Evidence: the same diff makes agents merge unprompted. The c0036 wording is now false and will mislead the next reader. `design: draft` conflicts with the tracker rule that a raft needs `ready` issues (`tracker.sh start` refuses otherwise), though these ship as direct skill chores.
Fix: reword the c0036 non-goal to "Merging itself is c0037". Fill the Solution line in both docs or set `design: ready`.

### F8 [low] The AC checks are grep-only and can pass with contradicting prose
Where: `tracker/issues/c0037/check.sh` ac1-ac4, `c0036/check.sh`
Evidence: `ac2` passes if the sentence "Agents never merge" is only reworded ("Agents must not merge"). `ac3` passes on any `significant` in three sections. Nothing checks that "human merges" or "asks" is gone from any skill. Nothing checks for `--admin` beyond the literal `Never use`. That is proportionate for a prose change, but it means the checks cannot detect the contradiction F7 describes.
Fix: optional. Add a negative grep over `.claude/skills` and `tracker/issues` for `human merges|Agents never merge|only when the human asks`.

## Judged criteria (code mode only)
None defined.

Verdict: changes

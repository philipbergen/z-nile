# Review 004: c0350 with c0340 and c0360 (code mode)
Inputs: e21dd33 (`git diff main...HEAD`); `.claude/skills/{tracker,execute-raft,review}/SKILL.md`; `tracker/issues/c0340`, `c0350`, `c0360` (docs and check.sh); `scripts/tracker/main.luau` (`reviewProblem`, `done`, `renumber`); `scripts/ci-verify.sh`; `.github/workflows/check.yml`; review-001..003 and refute-001..003. I ran `c0340/check.sh` and `c0350/check.sh` (all pass). I did not rerun `scripts/check.sh --full` (skill prose only).
Dropped from review-003: F1, F2, F3, F4.

Round-3 fixes verified: F1 (a refuted high or failed Judged criterion now triggers a re-review, step 6 last bullet, AC8) closes the pure-refutation hole, and together with the review-003 rule leaves no path where a high is answered only by its author. F2 (AC5 wording and label) now matches the tracker skill. F3 (`$'...'` body, `mergeCommit` sha) works in bash and zsh. F4 (`UNKNOWN` re-poll, `origin/main` comparison) is present. No high finding remains. One accepted consequence stands: `review-003.md` contains a high (F1), so under this PR's own rule the merge is blocked and the human decides. The findings below are what the round-3 edits left inconsistent or unrunnable.

### F1 [medium] The final-report template does not match Phase 6 (no MERGED status, no merge sha), and cleanup failures cannot reach a report that is already posted
Where: `execute-raft/SKILL.md` "Final report format" (unchanged by this diff) vs Phase 6 steps 2-3; `tracker/SKILL.md` After merge step 1
Evidence: Phase 6 step 2 says the report carries the merge commit sha (c0350 AC7), but the format block has only `R0010: <title>. <READY | BLOCKED>`, `PR:`, `Criteria`, ... and no sha line. An agent that follows the template, which is the thing it copies, omits the sha and calls a merged PR `READY`. `ac7()` greps only the Phase 6 prose, so it passes anyway. Separately, After merge step 1 says on a failing `pull --ff-only` or unclean worktree to "say so in the report", but Phase 6 posts the report on the PR before cleanup and step 3 then says to give "the same report" in the reply. The cleanup outcome exists only after the report is posted, so it can be recorded nowhere.
Fix: change the header to `<MERGED | READY | BLOCKED>` and add `Merge: <sha>` to the template. In Phase 6 step 3, say to add a one-line `Cleanup:` note to the reply (and a short follow-up PR comment if something was skipped), and point After merge step 1 at that note instead of "the report". Extend `ac7` to grep the template for the sha.

### F2 [medium] The `discard_changes` precondition is unsatisfiable whenever `main` has moved past the squash, and no fallback is given
Where: `tracker/SKILL.md` After merge step 2 (first bullet)
Evidence: The skill says to pass `discard_changes` only after "checking the diff against `main` is empty, as it is after a squash merge", comparing with `origin/main` after `git fetch`. A squash commit has a different tree from the branch tip as soon as any other PR merges after it (or as soon as `main` moved before the squash and the squash merged it in). `git diff origin/main HEAD` is then non-empty although every branch change is on `main`. With several rafts in flight this is the ordinary case. The compliant agent then cannot call ExitWorktree `remove` and has no other rule, so it either stalls or breaks the precondition. The claim "as it is after a squash merge" is true only on a quiet `main`.
Fix: use a check that is independent of what happened to `main`: the PR is `MERGED` and `git rev-parse HEAD` equals `gh pr view <pr> --json headRefOid -q .headRefOid` (everything on the branch was in the merged PR), plus `git status --porcelain` empty. Drop the `main` diff.

### F3 [low] BLOCKED after `done` contradicts the Stop conditions ("leave the PR in draft"), and "no unresolved `BLOCKED:` comment" has no way to be resolved
Where: `execute-raft/SKILL.md` Stop conditions "To escalate" step 3 vs Phase 6 step 1; `tracker/SKILL.md` Merging step 1 and the last paragraph
Evidence: After `done` the PR is ready. Phase 6 and Merging say "leave the PR as it is" and post `BLOCKED:`, while the escalation procedure says to leave it in draft. A ready PR with a `BLOCKED:` comment invites a human to merge it. Merging step 1 also requires "no unresolved `BLOCKED:` comment", but nothing defines resolved (a later comment from the human? a reply from the agent?), so a later agent run cannot tell.
Fix: for a post-`done` block, say `gh pr ready --undo` (or state explicitly that a ready PR stays ready) and define resolved as "a later human comment that starts with `UNBLOCKED:`".

### F4 [low] The round cap and step 6 triggers still disagree for round 3, and step 7 forces a false `refuted` on a medium that the author simply fixes
Where: `execute-raft/SKILL.md` Phase 4 steps 6-7
Evidence: Step 6 says re-review if fixes exceed about 15% of the PR or change the design; step 7 caps at three rounds and continues to Phase 5. A round-3 medium that the author fixes at length has no reviewer to check it, and the text does not say whether a fixed round-3 medium is allowed. Step 7 reads as mandatory: "file each ... answer it ... `refuted: below the merge threshold`". A fixed medium recorded as `refuted` is exactly the dishonest answer c0360 exists to remove, and it files a backlog issue for something already fixed.
Fix: one sentence: in round 3, a medium or low may be fixed only if the fix is small and local (no API or design change, well under 15%), answered `fixed <sha>`; otherwise file it and use the interim form.

### F5 [low] Merging step 4 allows a "clean" merge of `main` after `done`, but nothing detects a duplicate ID that merges cleanly
Where: `tracker/SKILL.md` Merging step 4; `scripts/tracker/main.luau` (`renumber`, no duplicate-ID check anywhere in `scripts/tracker` or `tests`)
Evidence: After `done` this raft's items live under `done/` while a colliding item from `main` sits at the backlog path, so the two merge with no textual conflict. The step tells the agent to renumber only if the merge conflicts or it notices, and `check.sh --full` has no duplicate-ID test to notice for it. The window is small (after Phase 5 step 2), but the path is autonomous and fails open.
Fix: after any post-`done` merge of `main`, add "run `tracker.sh list` and confirm no ID appears twice" to step 4.

### F6 [low] c0350 lists its ACs out of order relative to `check.sh`
Where: `tracker/issues/c0350/c0350-auto-merge-when-verified.md` "Checked" (order AC1-5, AC8, AC9, AC6, AC7); `check.sh` (order AC1-9)
Evidence: the template says each AC "maps 1:1 to a `check` line ... in the same order". The round-3 edits appended AC8 and AC9 mid-list.
Fix: renumber or reorder so the doc and `check.sh` agree.

## Judged criteria (code mode only)
None defined.

Verdict: changes

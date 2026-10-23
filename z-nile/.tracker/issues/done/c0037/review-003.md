# Review 003: c0037 with c0036 and c0038 (code mode)
Inputs: ef98766 (`git diff main...HEAD`); `.claude/skills/{tracker,execute-raft,review}/SKILL.md`; `tracker/issues/c0036`, `c0037`, `c0038` (docs and check.sh); `scripts/tracker/main.luau` (`reviewProblem`, `done`, `activeRaft`, `renumber`); `scripts/ci-verify.sh`; `.github/workflows/check.yml`; review-001/002 and refute-001/002. I ran `c0036/check.sh` and `c0037/check.sh` (all pass). I did not rerun `scripts/check.sh --full` (skill prose only). Repo setting `delete_branch_on_merge` is true, so "GitHub deletes the remote branch" holds.
Dropped from review-002: F1 (the round-3 referee and the audit gap are fixed; a different hole is F1 below), F2, F3, F4, F5, F6.

Round-2 fixes verified: the round-3 rule now keys off the reviewer's own file; the post-`done` step is plain git and fails closed with `BLOCKED:`; the report is posted before cleanup; the CI check is one runnable `gh pr view` query; the CI check and `MERGED` confirmation are concrete; c0037 names c0038. The remaining problems are below.

### F1 [high] A high finding that the author refutes in round 1 or 2, with nothing else triggering a re-review, merges with no reviewer having ruled on the refutation
Where: `execute-raft/SKILL.md` Phase 4 step 6 (re-review triggers) and the parenthetical in step 7 ("Rounds 1-2 need no such rule: a fresh reviewer in the next round rules on every refutation"); `scripts/tracker/main.luau:410-440` (`reviewProblem`)
Evidence: The step 6 triggers are "a high finding was **fixed**", API or design change, fixes over 15% of the PR, a Judged criterion ruled fail. A refuted high is none of these. Scenario: `review-001.md` has `F1 [high]` plus a verdict of `changes`. The author writes `- F1: refuted: <argument>`. No fix commit exists, so no trigger fires and there is no `review-002.md`. `reviewProblem` accepts any line starting with `refuted`, `done` passes, and Phase 6 merges (the "significant" rule reads only `review-003.md`). So the claim in step 7 is false for exactly the case where the author disagrees with a high, which is the case where a second look matters most. The same holds for a round-2 high that is refuted, and for a mix (one high fixed, another refuted): the re-review triggers, but the reviewer of the next round is told nothing to re-rule on the earlier refutation beyond "re-reads the previous review and refute files", which the review skill does say, so only the pure-refutation case is open.
Fix: add a step 6 trigger: "any high finding or failed Judged criterion was answered `refuted` rather than fixed", so a fresh reviewer must rule on it. Alternatively, make step 7's rule apply to every round: a high still open (refuted, not fixed) at the latest review blocks the merge. The first is the smaller change, and the round-3 rule then covers the last round.

### F2 [medium] c0037's AC5 still promises "a new clean review round" after `done`, which the skills now forbid; check.sh's AC5 label repeats it
Where: `tracker/issues/c0037/c0037-auto-merge-when-verified.md` "Acceptance criteria / Checked" AC5; `tracker/issues/c0037/check.sh` line for AC5
Evidence: The doc says "code changes after `done` get a new clean review round". `tracker/SKILL.md` Merging step 4 says the opposite: anything beyond a clean merge or an ID renumber is `BLOCKED:`, "a finished PR gets no unreviewed code changes". The check's label says "re-review after code changes", but `ac5()` greps only for `CLEAN`, `headRefOid`, `SKIPPED` and `BLOCKED:`. The acceptance contract for the change therefore states behavior the shipped skills contradict, and the check would pass either way. This is the kind of doc-versus-skill contradiction round 2 asked to be closed; it was fixed in the skills but not in the AC text.
Fix: reword AC5 to "`CLEAN` merge state, an empty or `SKIPPED` gate is not green, and a post-`done` change beyond a clean merge or ID renumber is `BLOCKED:`", and align the label. Note that `check.sh` is sequestered by the tracker skill only during a raft's execution, and c0037 has no `tracker: start` commit, so this edit is allowed.

### F3 [low] The merge command cannot produce a trailer, and the report's "merge commit sha" has no source
Where: `tracker/SKILL.md` Merging, the `gh pr merge` line; `execute-raft/SKILL.md` Phase 6 step 2
Evidence: In `--body "<summary>\n\n<Co-Authored-By ...>"` the `\n` inside double quotes is a literal backslash and `n` in bash (and in zsh's `"..."`). The squash commit message then has one line ending in `\n\nCo-Authored-By: ...`, and Git does not parse that as a trailer. Phase 6 step 2 asks for the merge commit sha but no command yields it: `gh pr merge` prints no sha; `gh pr view <pr> --json mergeCommit -q .mergeCommit.oid` does (review-002 F3 suggested it, but the skill text did not adopt it).
Fix: build the body with `$'...'` or `printf`/`--body-file -`, and name `gh pr view <pr> --json mergeCommit -q .mergeCommit.oid`.

### F4 [low] Transient merge states and the ExitWorktree `discard_changes` precondition are not covered
Where: `tracker/SKILL.md` Merging step 4; After merge step 2
Evidence: (a) Right after a push or `gh pr ready`, `mergeStateStatus` is commonly `UNKNOWN` (GitHub is still computing), and `mergeable` is `UNKNOWN`. Step 4 says any state other than `MERGEABLE` and `CLEAN` is "not mergeable", and the fallback reads as an immediate `BLOCKED:` stop, so a compliant agent aborts on a transient value. Say to re-poll `UNKNOWN` for a short while first. (b) "Pass `discard_changes` only after checking the diff against `main` is empty, as it is after a squash merge": if After merge step 1 was skipped or failed (root `main` not updated), a diff against the stale local `main` is not empty, and the agent has no rule for that case. Compare with `origin/main` after `git fetch origin main`.
Fix: one sentence for each.

## Judged criteria (code mode only)
None defined.

Verdict: changes

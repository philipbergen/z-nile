# Review 005: R0043 (design mode)
Inputs: prep worktree at 2330c43. I read `tracker/rafts/R0043/{R0043.md,check.sh,harvest.md}`, `design-review-00{1..4}.md`, `design-refute-00{1..4}.md`, `tracker/issues/c0114/{c0114.md,check.sh}`, and the fix delta `git diff 48d3e6c 2330c43`. I also ran `scripts/tracker.sh capture c0114` and `scripts/tracker.sh lessons --when design --full`. In the prototype `.worktree/proto-c0114` (4d3f21d) I ran the new AC13 line read-only, and I ran its mutants in a scratch clone outside the repository, with no remote and `origin/main` set by `update-ref`.
Dropped from design-review-004: none. F1 and F2 are fixed as the refutation says.

Fix delta. The new line `git diff --quiet origin/main...HEAD -- tracker/next z-nile/next` gave these results:
- The prototype exits 0, and so does this prep branch, so the line isn't red between steps.
- It kills each of these mutants with exit 1:
  - round 2's copy to `z-nile/next`;
  - an edit to `tracker/next`;
  - deleting `tracker/next`.
- A merge of a main that raised `tracker/next` stays green, because the three-dot form diffs from the merge base. This is the case that matters during execution.
- It goes red only when the local `origin/main` is older than the main the branch merged. Fetches only move that ref forward, so a normal flow can't reach that state. RC1 (`-- src`) has the same shape.
- An unknown ref makes git exit 128, so the line fails closed.

`tracker/next` and `z-nile/next` have left Touched modules, which now agrees with §5.

Scope fidelity (item 11): the capture is unmarked and unchanged since round 4. Every remaining outcome still has a Checked criterion. No scope finding.
Guesses: the ten "pending user" guesses are unchanged and still reasonable.
Repository safety (item 9): the new line is a read-only `git diff`, and `AC_LIST=1` lists it without running it. The delta writes nothing and weakens no guard.
Lessons (item 10): no lesson file changed since round 4. The harvest maps round 4's findings to existing lessons, so there is no restated finding to judge.

### F1 [low] The new AC13 Rules row says `reasoned`, but its command exists and runs
Where: c0114 Rules and mutants, row "the PR never touches `tracker/next` or `z-nile/next`"; Verification log
Evidence: the row is marked `reasoned`, but the command can run on a prototype. I ran it: it exits 0 on proto-c0114 4d3f21d and on this prep branch. It exits 1 for each of the three mutants (copy to `z-nile/next`, edit `tracker/next`, delete `tracker/next`). It exits 0 after merging a main that raised `tracker/next`.
Critique: lesson ticket-prep/prove-specs-pass-on-a-prototype asks for the run to be recorded. Leaving it out costs nothing at execution.
Consequences: none.
Recommendation: mark the row `run: killed` and add these results to the Verification log.
Lesson: ticket-prep/prove-specs-pass-on-a-prototype

### F2 [low] Rollback step 2 doesn't say when `z-nile/next` is read, so the copy can go stale while the rollback PR is open
Where: R0043 Risks & rollback, step 2
Evidence: until the rollback lands, the c0114 engine on main keeps numbering on `z-nile/next`. If someone copies `z-nile/next` into `tracker/next` when the rollback PR opens, every number reserved before it merges is handed out again. That is the reuse the step warns against.
Recommendation: say that the copy is made from `origin/main` immediately before the rollback merges. If main moved in between, the PR merges main again and the copy is redone.

Verdict: approve

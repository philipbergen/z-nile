# Review 004: R0043 (design mode)
Inputs: prep worktree at cbd99e6: `tracker/rafts/R0043/{R0043.md,check.sh,harvest.md,design-review-00{1,2,3}.md,design-refute-00{1,2,3}.md}`, `tracker/issues/c0114/{c0114.md,check.sh,acceptance/*}`, and the fix delta `git diff 29af811 cbd99e6`. Also `scripts/tracker.sh capture c0114`, `scripts/tracker.sh lessons --when design --full`, and the tracker skill (Merging) and execute-raft (Phase 6). Prototype `.worktree/proto-c0114` (8804fad moves, 4d3f21d edits): it leaves `tracker/next` and `z-nile/next` untouched against its base 2a3a0a0, and has 56 changed promoted specs, matching the Overrides list. I read `publish.counterOf`, `publish.allowed`, `publish.commit`'s migration, `reserve`, `reserveOnOrigin`, `localCounters`, `cmd.new`'s emergent path, `cmd.spend`, compaction's counter write and audit's counter rules. I ran one mutant in a scratch clone outside the repository (no remote, `PICKMAN_PUBLISH=0`); see F1.
Dropped from design-review-003: none. F1 to F4 are fixed as the refutation says. Option (B) removes the merge conflicts, `resolveCounterMerge` and `counter-behind`. Every merge of main into the branch is now plain, and the window spec shows the lease race during the move. The mechanism holds. Its one remaining gap is that nothing checks its premise on the real branch (F1).

Scope fidelity (item 11): the capture is unmarked and unchanged. Title, Problem and Solution are verbatim, apart from the decided lines and the inline "superseded" note. Every remaining outcome has a Checked criterion. No scope finding.
Guesses: the ten "pending user" guesses are unchanged and each is reasonable as stated.
Repository safety (item 9): the changed specs (window, layout, compact-roots, roots-cli) write only to their `.cache/c0114-*` fixtures and read the real `z-nile/projects.toml` and `tracker/next` read-only. The migration is engine code that pushes only through `publish.commit`'s lease push, and only from a tree whose base already has the registry, which no fixture-free check run has. The delta weakens no guard.
Lessons (item 10): the two lessons changed since round 3 are general rules another raft could fail: the rewritten ticket-prep/design-the-execution-window, and the anchoring note on testing/plain-find-for-literals.

### F1 [medium] "The branch never touches `tracker/next`" is the premise of the whole counter mechanism, but no check reads the real branch, so the round 2 design passes every criterion
Where: c0114 AC13, AC2, AC12; `check.sh` AC13 label; §5; Touched modules
Evidence: AC13's label and text start "the branch never touches tracker/next", but `window.spec` runs only in its `.cache/c0114-window` fixture. I made the mutant "the branch moves the counter itself": `cp tracker/next z-nile/next`, then the tombstone at `tracker/next`, committed in a scratch clone of the prototype. The results:
- `./zn audit`: "0 errors, 0 warnings", so AC12 passes. Audit reads the state as already migrated.
- `layout.spec`: 7/7, so AC2 passes. It takes the "moved on origin" branch of its if.
- `window.spec`: 4/4, so AC13 passes.

JC1 judges only the `c0114: move` commits, so a later edits commit that writes the tombstone is outside its rubric. An executor who keeps the original §1 row ("`tracker/next` → `z-nile/next`, `git mv`") passes every check. That implementation brings back design review 003 F1: every capture on main conflicts with the branch, and the merge after `done` is BLOCKED. Lesson ticket-prep/spec-design-correspondence asks "does every check's label say exactly what its command verifies?", and this label claims more than its command checks.
Also, Touched modules still lists `tracker/next` and `z-nile/next`, which contradicts §5.
Critique: the tempting fix is to make layout.spec require `z-nile/next` to be absent. That spec is promoted and later runs on main, where `z-nile/next` exists after the migration, so it would turn red there.
Consequences: the check has to run only on the branch, before `done`. A `check.sh` line does that, because a done item's `check.sh` is only listed, never rerun. It must not depend on main's moving tip (lesson ticket-prep/no-check-red-between-steps). The three-dot diff compares against the merge base, so it depends only on the branch.
Recommendation: add a Checked line to c0114's `check.sh`, for example `check "AC13: the branch never touches the counter" git diff --quiet origin/main...HEAD -- tracker/next z-nile/next`. The command is read-only and lists cleanly with `AC_LIST=1`. Add a Rules row: rule "the branch never touches either counter file", mutant "a branch commit writes `z-nile/next` and the tombstone", killed by that line. Record the run. Remove `tracker/next` and `z-nile/next` from Touched modules.
Lesson: ticket-prep/spec-design-correspondence

### F2 [low] The rollback line is no longer true under (B): reverting the PR leaves the tombstone, so the restored engine refuses to number
Where: R0043 Risks & rollback, "Rollback: revert the PR; the forwarders make the revert a clean inverse"
Evidence: the migration is its own commit on main, written by the first publish after the landing. It is not in the PR. `git revert` of the squash commit therefore keeps `z-nile/next` and the tombstone at `tracker/next`. The restored pre-c0114 engine then refuses `new issue`, `new raft` and `renumber` ("tracker/next on origin/main does not parse", E5).
The obvious repair is to revert the migration commit as well. That restores `tracker/next` to its counters at the moment of the move, so every number reserved on `z-nile/next` after the move is handed out again.
Tooling items published under `z-nile/.tracker/` after the landing also stay where the old engine can't see them.
Recommendation: state the procedure: revert the PR, then, in the same PR, write `tracker/next` with `z-nile/next`'s current counters, delete `z-nile/next`, and move any item created under `z-nile/.tracker/` since the landing back into `tracker/`. Never revert the migration commit on its own.

Verdict: changes

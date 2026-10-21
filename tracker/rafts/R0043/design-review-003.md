# Review 003: R0043 (design mode)
Inputs: prep worktree at 2113623: `tracker/rafts/R0043/{R0043.md,check.sh,harvest.md,design-review-00{1,2}.md,design-refute-00{1,2}.md}`, `tracker/issues/c0114/{c0114.md,check.sh,acceptance/*}`, and the fix delta `git diff a28d711 2113623`. Also `scripts/tracker.sh capture c0114`, `scripts/tracker.sh lessons --when design --full` and `--skill review`, the tracker and execute-raft skills (Merging, Phase 5 and 6), and origin/main's `git log -- tracker/next`. Prototype `.worktree/proto-c0114` (1b33f09 moves, a6b170c edits): its `z-nile/.tracker/issues/c0114/{acceptance,check.sh}` are byte-identical to the prep's. `bash z-nile/.tracker/issues/c0114/check.sh` gave 13/13, and `window.spec` alone 5/5. I read `resolveCounterMerge`, `mergeOrigin`, `reserve`, `reserveOnOrigin`, `counterBehind`, `publish.counterFor`, `publish.allowed` and `publish.commit`'s counter handling.
Dropped from design-review-002: none. F1 to F4 are fixed as the refutation says, but F1's mechanism has two more holes (F1 and F2 below).

Scope fidelity (item 11): the capture is unmarked and unchanged from the earlier rounds. Title, Problem and Solution are verbatim, apart from the decided lines and the inline "superseded" note. Every remaining outcome has a Checked criterion. No scope finding.
Guesses: the ten "pending user" guesses are each reasonable as stated, and none changed in this round.
Repository safety (item 9): the new `window.spec` changes only `.cache/c0114-window` (trackerfix; the worktree commits as `c0114-window@example.invalid`), and reads the real `z-nile/projects.toml` read-only. The delta weakens no guard.

### F1 [medium] The PR itself still edits `tracker/next`, so every counter raise on main after `done` makes the PR conflict, and the tracker skill's Merging rule then says BLOCKED
Where: c0114 §5, §11 "The execution window", Implementation step 9; tracker skill Merging step 4; execute-raft Phase 5 step 2 and Phase 6 step 1
Evidence: from step 2 on, the branch has changed `tracker/next` to the tombstone. Main's old engine raises that file with every capture and new raft: 16 times on 2026-10-20 alone (`git log origin/main -- tracker/next`). Any raise after the branch's last merge is a content conflict on `tracker/next` (design review 002's experiment). GitHub then shows the PR as `DIRTY`.
- §11 and step 9 resolve that conflict only through `./zn sync` and the publish merge-back, before `done`.
- After `done`, the PR still has to wait for the full gate, CI and the `beta` job, which can take 20 minutes. The skill that governs that stretch says: "If main moved since, and the merge is a clean one, merge `origin/main` in with plain `git` … If it conflicts … post `BLOCKED:` and stop".
- So a single capture landing in that stretch blocks the raft for the human. That is likely on a day like 2026-10-20.
- Execute-raft Phase 5 step 2 also tells the executor to merge with plain `git` before `done`. c0114 step 9 overrides that with `./zn sync`, but nothing connects the two documents for the executor.

This is the second hole in the mechanism review 002 F1 led to: the branch edits the old counter file, and every merge then repairs it. Lesson ticket-prep/design-the-execution-window asks "what does each merge of main do to the two copies?". The final merge after `done` is one of those merges.
Critique: the tempting fix is a sentence in §11 saying "after `done`, a conflict on `tracker/next` alone is resolved with `./zn sync`". That bends the skill's "a finished PR gets no unreviewed changes" rule for one raft. It also leaves a loop: each sync triggers a new CI and beta run, which another capture can conflict with again.
Consequences: whichever way is chosen has to cover every merge into this branch, the GitHub merge included. If the branch keeps changing `tracker/next`, that merge always races main's captures.
Recommendation: question the mechanism. The conflicts exist only because the PR changes `tracker/next`.
- **(B), preferred: the PR never touches `tracker/next`.** It moves no counter and writes no tombstone. `counterFor` stays decided from origin, but by the counter's own presence: `z-nile/next` when origin/main has it, else `tracker/next`. The first publish whose base has a registry and no `z-nile/next` migrates the counter in its own lease push: it writes `z-nile/next` (from `tracker/next`, raised if it reserves) and the tombstone at `tracker/next`. `publish.allowed` permits `tracker/next` only as that exact tombstone, only in that push. Execute-raft Phase 6 step 2's `./zn spend R0043 --phase deliver` is the first publish after the merge, so the migration happens minutes after landing.
  - What B removes: every merge conflict on the counter, `resolveCounterMerge`, `counter-behind` (and F2), and step 9's special sync.
  - Until the migration, old engines keep numbering on `tracker/next`, which is still the live counter. Afterwards they refuse (E5 is unchanged). A lost lease race retries on the migrated main.
  - What B changes: AC2's "tracker/next is a tombstone" becomes "after the first publish on a registry origin". `audit` accepts the state "registry, no `z-nile/next`, a parsing `tracker/next`" as a warning (`counter-unmigrated`), and reports `old-counter` only when `z-nile/next` exists. `localNumber` and audit's `next-missing` read the same choice locally. The JC1 moves commit no longer contains the counter.
  - Spec cases for B: an origin with a registry and no `z-nile/next` makes the first `new issue` push both files, with the tombstone at `tracker/next`. A second publish writes only `z-nile/next`. Writing a tombstone or a counter to `tracker/next` at any other time is refused. A merge of main into a branch from before B shows no conflict on `tracker/next`. Add a Rules row for each, with its mutant.
- **(C), if the author keeps the current mechanism:** state in §11 that, in the window, a conflict on `tracker/next` alone after `done` is mechanical, like renumbering colliding ids. It is resolved by `./zn sync` and followed by a gate rerun. Say so where the executor reads it (prompt, §11, step 9). Add a window case that runs `sync` on a branch whose raft is already in `done/`. Accept that a busy main can delay the merge repeatedly.

Either way, update the "How to apply" line of ticket-prep/design-the-execution-window to match the mechanism that holds. At the moment it teaches "make the merge of main resolve the two copies", which is the approach that breaks here.
Lesson: ticket-prep/design-the-execution-window

### F2 [medium] `audit`'s `counter-behind` compares against origin/main's current tip, so AC12 turns red whenever main gets a capture, including in the code reviewer's run
Where: c0114 §11 third sub-bullet; AC12, AC13; `window.spec` case "a counter-only reservation …"; prototype `counterBehind()` in `z-nile/engine/main.luau`
Evidence: `counterBehind` reads `origin/main:tracker/next` and fails when the working tree's `z-nile/next` is lower. The branch then needs no bad merge at all for the error: it is enough that main moved after the branch's last merge. The window spec pins exactly this case: after `renumber` raises origin, audit "before the merge" is expected to fail.
On the real raft:
- the code-mode reviewer runs `scripts/tracker.sh sync --fetch` (fetch only, never a merge), then `tracker.sh check c0114`. AC12 is red whenever a capture landed since the author's push, and the reviewer may only report it, as an unmet criterion;
- `done` runs RC0, which runs c0114's `check.sh` (several minutes). A capture during that run fails `done`;
- after `done`, AC12 can't be rerun without a merge, so F1's skill rule applies.

This is lesson ticket-prep/no-check-red-between-steps: a check that goes red because of work the process does only at a later step (here, the next sync).
Critique: the error is meant to catch a merge that dropped main's raises, as the `-X ours` case shows. Measured against the moving tip, it fires for a branch that did nothing wrong.
Consequences: under F1 (B) the check disappears. Under (C) it must measure what the branch has actually merged.
Recommendation: under (C), compare `z-nile/next` with `tracker/next` at `git merge-base HEAD origin/main`, the newest origin commit the branch contains. That result depends only on the branch. It still catches `-X ours`: after that merge, the merge base is the commit with `issue 70`. Change the window spec's second case to expect no `counter-behind` before the merge, and `counter-behind` only after a merge that kept the branch's side. Add a Rules row whose mutant compares against `origin/main`'s tip.
Lesson: ticket-prep/no-check-red-between-steps

### F3 [low] Stale figures after round 2
Where: c0114 §Affected specs, §Scalability, U1; R0043 Risks
Evidence:
- §Affected specs lists the new specs as `{registry,…,classified}`, without `window`.
- §Scalability and U1 still give 73.5 s as the gate time and mark U1 PASS ("within 10% of main's full gate", that is 78.5 s against 71.4 s). The latest Verification log entry gives 81.6 s, 14% over, and nothing reconciles the two.
- R0043 says "about 5,200 changed lines". The Size section says about 5,450.
Recommendation: add `window` to the list. Rerun U1 on a quiet machine and record the result, or note that 81.6 s was taken under load; the executor's step 8 measures it again anyway. Make the two line counts agree.

### F4 [low] Harvest: design review 002 F3 is filed under testing/plain-find-for-literals, which does not cover it
Where: `tracker/rafts/R0043/harvest.md`; `.claude/skills/testing/lessons/plain-find-for-literals.md`
Evidence: that lesson is about pattern characters in `string.find`, `match` and `gsub`. Review 002 F3 was an unanchored `grep -vF` that matched a root name anywhere in a path, not just as its prefix. The lesson's `check` would not catch it.
Recommendation: add a note to that lesson ("a fixed-string filter on paths must be anchored to the path start"), or file F3 under an anchoring lesson. The other lesson added since round 2, ticket-prep/design-the-execution-window, is a general rule; see F1 for its "How to apply" line.

Lesson candidate (for the lead):
- ticket-prep: when a raft moves shared state that main keeps writing, the branch should not edit the old copy at all. Every branch edit of a file that main writes often conflicts at every merge, the PR's own merge after `done` included. Migrate the old copy on origin at the first publish after landing instead. Why: F1, the second hole in the same counter mechanism. Check: "Does the branch change any file that main writes during the raft's execution, and if so, what resolves the conflict at the PR merge, after `done`?" (This could be a note on ticket-prep/design-the-execution-window.)

Verdict: changes

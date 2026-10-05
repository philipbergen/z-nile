# Review 004: R0270 (design mode)
Inputs: prep worktree at 7c6fa30 plus its uncommitted prep edits (R0270.md, check.sh; the c0870 and c0880 documents, check.sh files, acceptance/*.spec.luau, experiments/prototype.diff); design-review-001..003 and design-refute-001..003; the prototype worktree proto-r0270 at a911cdc; origin/main 515bd7e (`tracker.sh sync --fetch`: unchanged); AGENTS.md and the review, ticket-prep, testing and tracker skills; R0250's c0760 and c0780 and the draft c0890 (for fit).
The user's three decisions after round 3 (strict count by one, a one-off clean-slate compaction, `sync` unchanged) are binding and are not re-raised here.

What I verified:
- **The prototype matches the prep.** `git diff 515bd7e a911cdc` in proto-r0270 is byte-identical to `experiments/prototype.diff`, and all 11 spec files are byte-identical between the prep and the prototype. I ran them in the prototype: 87 passed, 0 failed, which matches E7.
- **Removing the skip left nothing behind.** `retire`, `retiredIds`, `retiredOf`, `localRetired` and `retired-id` are gone from both documents, the Rules and mutants tables, both test plans, the specs, both `check.sh` files, R0270, the tracker skill and the prototype's `scripts/`. The only mentions left are E7's record of the removal and R0270's and c0870's statements of the decision, and both are correct. c0880's code table, `ITEM_CODES`, AC1 and its `check.sh` labels no longer name it. remap.spec has no plain-merge case.
- **The round-3 answers hold.**
  - F5: `publishFresh` is the only `publish.commit` caller besides `cmd.remap` (main.luau:342 and :1200). `publish-guard.spec` is in the Test plan, in the Rules and mutants table and under AC4's check.
  - F6: AC4's text and its label agree.
  - F2: `refuseStale`'s message gives one way out per case, and the skill's Compaction bullet says the same thing.
  - Neither the R0250 risk nor c0760's spec conflicts: c0760's board-refresh spec has no `publish.commit` grep, so wrapping `published(...)` inside `publishFresh` satisfies both guards.

### F1 [medium] c0890, now in prep, moves promoted chore specs out of `tests/acceptance/`, and R0270 hard-codes that root in its compaction, its busy-ref test, its Overrides and its sequestered check.sh, without naming c0890
Where:
- R0270 Order & dependencies and Risks: neither names c0890;
- c0870 compact step 2 (`-- tracker tests/acceptance`), step 5(a) and (c), `ids.rewritePaths`;
- c0870 check.sh AC6 (thirteen literal `tests/acceptance/c0…` paths) and its fallback `A="$PWD/tests/acceptance/c0870"`, and the same in c0880's check.sh;
- the prototype's compact.luau:58-59 and :95, and ids.luau:117.
Evidence: c0890 (status `preparing`, commit 80f0cca) plans to move "`tests/tooling` and the chores' `tests/acceptance/c*`" into, for example, `tests/harness/`, and to route promotion by type. What happens depends on the landing order:
- **c0890 lands before R0270 executes.** The sequestered AC6 line names spec paths that no longer exist, and the executor hits a stop condition.
- **c0890 lands after R0270 but before the user runs the compaction.** `compact.apply` renames only `tests/acceptance/<old>` folders, `rewritePaths` rewrites only `tests/acceptance/<id>` tokens, and `busyRefs` ignores branches that change only `tests/harness/`. The harness folders then keep their old ids. After the compaction, `tests/harness/c0010` holds the specs of the item that is now, say, `c0005`. When the new `c0010` is done, its promotion lands in an occupied folder. Nothing in the gate notices, because no spec ties a promoted folder's name to its item.
- **R0270 lands first and c0890 forgets compact.** This is the same defect, reached from c0890's side.
Critique: today R0270 is coherent on its own. The risk is two rafts, both in prep at the same time, that each assume the promoted-spec root. The tempting fix is to make the root a parameter now, but c0890 has no design yet, so the new path is unknown.
Consequences: one extra decision for the user: the order. If c0890 goes second, its design must also cover `compact.apply`, `ids.rewritePaths`, `busyRefs` and `renamed`'s two-part rule. If it goes first, R0270's sequestered check.sh and Overrides must be re-prepped.
Recommendation: put the order to the user in the prep report, then record it:
- Add a Risks bullet to R0270: "c0890 (in prep) moves promoted chore specs. R0270 lands first, and c0890's design extends `compact.apply`'s folder moves, `ids.rewritePaths`, `busyRefs` and the testing skill's two-part rule to every promoted-spec root. The user runs the compaction before c0890 merges, or after it with that extension in place."
- Add a mirrored note to c0890's Solution, for example under "Watch the interactions". It costs nothing now and keeps either reviewer from approving a raft that silently breaks the other.
- If the user picks c0890 first, R0270 goes back to prep for the paths. Make no spec change now.

### F2 [low] Wording left over from earlier rounds contradicts the current remap design
Where and evidence:
- R0270 Whole-raft design diagram: `remap --origin's map + counter--> compact.apply --> commit (then: git merge origin/main)`. Since round 2, remap merges `origin/main` itself against a remapped base (c0870 remap step 4), and a plain `git merge` is what E2 showed fails.
- remap.spec header comment: "and commits, so that merging origin/main afterwards is clean". The spec itself asserts that `HEAD^2` is `origin/main`.
- c0870 remap step 2 says the reservation twice ("one `publish.commit` raises the counter past the last of them, … reserved by one `publish.commit` of the counter when publishing"). It reads as two pushes.
- R0270 Order says "c0870 steps 2-7" and leaves out step 8, the trial compaction that Risks relies on.
Critique: specs and Rules rows kill the wrong implementations (the "plain `git merge`" mutant was run), so this is clarity only. But the diagram is the first thing an executor reads.
Consequences: none.
Recommendation:
- Diagram: change the end to `--> commit --> merge-tree against the remapped base`.
- remap.spec's comment: "…commits, and merges origin/main itself against the remapped merge base". Prep may still edit the file.
- Step 2: say it once: "one `publish.commit` of the counter raises it past the last of them (offline: origin's value, nothing written)".
- Order: "c0870 steps 2-8".

### F3 [low] The skill forbids a plain merge first but gives no way back from one, and afterwards `remap` refuses
Where: the tracker skill's Compaction bullet ("Never merge it plainly first: nothing detects the mixed tree afterwards"); c0870 remap step 1; the prototype's main.luau:1159.
Evidence: a busy branch runs `tracker.sh sync` (as the skills say) or `git merge origin/main`. Its local `tracker/compaction.txt` now equals origin's. `tracker.sh remap` then refuses with `this branch already has the compaction`, and `refuseStale` lets every publish through. The agent has no documented way out, and the decision accepts only non-detection, not being unable to recover.
Critique: under the user's decision this is out of the tooling's scope, but one clause of guidance is cheap and changes no behaviour.
Consequences: none (no code change).
Recommendation: add one clause to the Compaction bullet: "if you merged first, undo that merge before anything else (`git reset --hard ORIG_HEAD`, or the commit before the merge if you have already pushed it), then run `remap`". Add no spec. If the executor wants one, skill-doc.spec can assert `ORIG_HEAD` on that line.

### F4 [low] Two rafts edit the same one-line skill bullet, and the "Published or carried" list does not show the new counter-only pushes
Where:
- the tracker skill's "The direct-push exception" bullet: c0870's skill-doc.spec requires `` `tracker/next` `` and "only go up" on that line, and R0250's c0780 check.sh line 34 requires `tracker.sh land` on the same line;
- the "Published or carried" bullet, which lists `new issue`, `new raft`, `status`, `start`;
- R0270 Risks (the R0250 bullet covers only `publishFresh`).
Evidence:
- Whichever raft merges second gets a text conflict on that line. A resolution that keeps only one side's words fails the other raft's promoted check.
- Separately, after c0870 an emergent `new issue --raft` and `renumber <id>` without `<new>` also push to `origin/main`: a counter-only commit, even from a raft branch's worktree. "Published or carried" does not say so, and an agent reading it assumes those commands stay local.
Critique: clarity, plus a merge hazard that is easy to resolve once it is named.
Consequences: none.
Recommendation:
- Extend R0270's R0250 risk bullet: "both rafts edit the direct-push exception line: keep `tracker/next … only go up` and `tracker.sh land` on that one line".
- Add to "Published or carried": "an emergent issue and `renumber` without `<new>` publish only the raised counter".
- Assert the latter in skill-doc.spec under AC5, as a Rules row run against the prototype.

### F5 [low] `publish-guard.spec` is evaded by an alias, and the per-case stale message is pinned only by the word "remap"
Where: publish-guard.spec `callers` (looks for `publish.commit(` only); remap.spec "a branch from before the compaction cannot allocate" (asserts `has(stderr, "remap")`).
Evidence:
- `local commit = publish.commit` at the top level, followed by `commit(".", …)` inside a new `cmd.ready`, passes the guard.
- The round-2 message (`merge origin/main, or run tracker.sh remap…`), which refute 003 F2 replaced, would also pass remap.spec.
Critique: both are backstops behind code review. The fixes are cheap and keep the round-3 answers from regressing silently.
Consequences: an alias inside `publishFresh` itself is still allowed, which is fine.
Recommendation:
- In `callers`, match the bare token `publish.commit` (comments stripped), not `publish.commit(`.
- In remap.spec, assert `a branch that changed tracker/ runs tracker.sh remap`.
- Record both cases against existing Rules rows, with their mutants (an alias; the old message) run against the prototype.

Verdict: changes

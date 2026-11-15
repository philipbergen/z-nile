# Review 001: d0295 (design mode)
Inputs: 8d8c9ecc5ed8c98ef1afa1aed7f3a6cc930331a7 (prep-raft-order-names-non-members). `z-nile/.tracker/issues/d0295/d0295.md`, `check.sh`, `acceptance/order-section.spec.luau`, `order-ready.spec.luau`, `order-cli.spec.luau`, `order-docs.spec.luau`, `experiments/order-scan.luau`, `experiments/prototype.patch`; `z-nile/engine/stack.luau`, `layergit.luau`, `workread.luau`, `readycheck.luau`, `readyfacts.luau`, `main.luau` (`setStatus`, `renderPrompt`, `cmd.ready`, `cmd.stack`); `z-nile/templates/prompt.md`, `templates/raft/doc.md`; z-raft SKILL.md and its two lessons; `./zn capture d0295` (capture 36c31017). Runs: `tests/tooling/repo-fence.spec.luau` on this tree; the selector on every Touched path; a scratch copy of order-scan using `stack.order` (`.cache/d0295-review/scan.luau`); greps of promoted and sequestered specs for the touched files, the template text and fixture Orders.

### F1 [high] check.sh names `GIT_CONFIG_`, so the gate's repo-fence spec fails on the prep tree
Where: `z-nile/.tracker/issues/d0295/check.sh:18-22` (`nostep`); Unknowns E4
Evidence: `lune run tests/run -- tests/tooling/repo-fence.spec.luau` from `z-nile/` on 8d8c9ecc fails: `FAIL … no spec, check.sh or script switches a guard off or points git elsewhere … checks must not override the repository guards: z-nile/.tracker/issues/d0295/check.sh names GIT_CONFIG_`. The scan's `sources()` reads every `check.sh` under every project root, unfinished ones included, and `GIT_CONFIG_` is on its `NAMES` list. (The run's other failure, "specs have no GitHub credentials…" at line 593, comes from this dispatched step's git wrapper catching `-c`. That is d0355/d0298, not d0295.) `lune run z-nile/affected -- z-nile/.tracker/issues/d0295/check.sh` selects nothing, so the prep PR's `--affected` may pass. The first `--full` (the merge's, the post-landing net) then fails, and main is red for every later full run.
The unset also goes further than E4 needs. E4's failures come from the broker (`ZN_PUBLISH_*`) and the wrapper (`z-nile/bin`, `ZN_REAL_GIT`); neither involves `GIT_CONFIG_*`. This step's environment has `GIT_CONFIG_COUNT=4`: `credential.helper` reset to empty, then the agent-token helper, twice. Unsetting the count drops that reset, so the user's own credential helper from their global git config (the keychain) comes back for the runner's top process and everything else `nostep` starts outside the jail. That undoes the credential boundary the dispatcher sets. d0298 (prepared, R0096) lists `GIT_CONFIG_*` in `fence.STEP_HANDLED`: fence.sh already replaces those entries for every spec, so stripping them gains nothing. The helper also names only KEY/VALUE 0 and 1, while the step now carries 0 to 3.
Critique: the tempting fix is an `ALLOWED` entry for d0295's check.sh in `repo-fence.spec.luau`. That edits a guard's allow-list for convenience (zz-test/narrow-guard-allowances), and no allowance is needed at all.
Consequences: without the `-u GIT_CONFIG_*` arguments, check.sh's own commands keep the step's entries: the agent helper answers with an empty token, because `ZN_AGENT_GH_TOKEN` is still unset, and the user's keychain stays reset. fence.sh replaces the entries for the specs. Both of E4's causes are still removed. Interactive runs are unchanged.
Recommendation: drop the five `-u GIT_CONFIG_*` arguments from `nostep` and keep the `ZN_*` unsets and the PATH filter. Reword E4's "the set d0298's E1 strips" to the set it now strips, citing d0298's `STEP_HANDLED` for `GIT_CONFIG_*`. Rerun AC3 and AC6 through check.sh in a dispatched step and record the result. Run `tests/tooling/repo-fence.spec.luau` on the prep tree, record it in E7, and add it to the Regression guard (it scans this check.sh). Do not edit `repo-fence.spec.luau`.
Lesson: z-design/prove-specs-pass-on-a-prototype

### F2 [medium] "An Order start would refuse" is narrowed to the Order text's faults, and nothing records or pins that choice
Where: Non-goals bullet 1; Solution; AC1, AC2; Rules and mutants row 3; `experiments/order-scan.luau`
Evidence: the capture asks that "z-raft's own checks (status prepared) refuse an Order that start would refuse, before the raft is readied". Take a raft whose Order is "By id." and whose two members depend on each other. `start` refuses it (`stack.order`: "dependency cycle among: c0070, c0080"), but the design keeps `status <R> prepared` accepting it and defers the case to d0360. There is no `Scope decision (user, …)` or `Decided with the user` line. The stated reason, c0067's R0060, applies to `ready` only. That fixture seeds R0060 already prepared (`tests/acceptance/c0067/ready.spec.luau:255-279`) and never runs `status R0060 prepared`, so refusing a cycle in the carried move needs no Override.
Nothing pins the narrower choice where the capture names it. A carried move written as `select(2, layergit.order(raftItem))` (the full `stack.order`, the function AC5 already calls) passes every check in check.sh: no case runs `status <R> prepared` on a cyclic raft.
AC5's scan also disagrees with the split. It judges `layergit.order`, cycles included, while the commands judge `stack.orderProblem`. If a prepared raft with a member cycle is on main at execution, AC5 goes red, and no Migration rule can fix it: the cycle is in the members' `depends_on`, which is d0360's.
Critique: the reading is defensible, since the cycle's message names no Order. But it is the author's reading, and it narrows the literal captured outcome. The tempting fix is one sentence restating the Non-goal.
Consequences: refusing a cycle at status prepared only would make the carried move stricter than `ready`/`work` until d0360 lands, and z-raft §5 would have to say which command refuses what.
Recommendation: escalate to the user:
- (a) Confirm the reading: the commands before `start` refuse the Order text's faults, and cycles stay with d0360. Cost now: none; a cyclic raft is still readied and refused at `start` until d0360. Record it as `Decided with the user`, and add an order-cli case where `status <R> prepared` takes a raft whose two members depend on each other, with Order "By id." (this kills the full-`stack.order` mutant). Then either switch order-scan to `layergit.orderProblem`, so AC5 asks only what the migration can fix, or keep `layergit.order` and say what AC5 does when a cyclic prepared raft appears.
- (b) Keep the literal scope: the carried move runs the full `stack.order` (no Override needed), and so do `ready`/`work`, with c0067's case overridden by a chore in `depends_on`. This folds d0360 in. Cost: one Override chore, c0067's case narrowed, d0360 retired, and cycle cases added to AC1 to AC3.

Under either option, a status-prepared case on a cyclic raft pins the choice.
Lesson: z-design/never-narrow-captured-scope

### F3 [medium] The Migration rule rewrites a multi-member raft's Order to the fallback order, against its reviewed order
Where: Design, Migration; Implementation step 6; Touched modules
Evidence: the rule makes the Order "one line naming the members joined by ', then ' in `stack.order`'s fallback order (`depends_on`, then id)", and it runs "over whatever the scan then lists" at execution time. Take a prepared raft with members c0290 and c0300, no `depends_on` between them, whose reviewed Order reads "c0300, then c0290: c0300's new type is what c0290 calls. R0100 merges before c0264's raft." The scan refuses it on c0264. The rule then writes "c0290, then c0300." and moves the reason under Cross-raft waits, which "is never read as a layer". `start` now stacks c0290 first, against the Order the coherence review approved.
Today's list is safe only by luck: my run of the scan's logic on 8d8c9ecc lists R0030, R0066, R0074, R0080 and R0109, all with one member or none. But E2 itself says the defect "recurs with every rafting until this lands", and prepared rafts can have several members (R0094 has three).
Three smaller gaps in the same rule:
- Ten rafts already have a `## Cross-raft waits` section (the lesson told authors to write one). A listed raft that has one would get a second under the rule's "a new section", and `main.raftSection` renders only the first.
- Step 6's "Run `experiments/order-scan.luau` from the root" is a bare `lune run`, which the PreToolUse hook refuses.
- R0109, and any raft listed later, is not in Touched modules.

Critique: the tempting fix is "keep the members in the order written". That needs a definition when the text repeats a member (the layer-branch spelling) or names non-members, and a written order that contradicts `depends_on` is refused anyway.
Consequences: keeping the old order needs no new review, because the meaning is unchanged. A raft whose old order contradicts `depends_on` cannot be migrated mechanically.
Recommendation:
- The new Order line names the members in the order `stack.order` gives on the old Order text, after removing every non-member id and every repeat after the first. That is first-mention order, then the unnamed members in fallback order.
- If that order is refused ("listed before"), list the raft for its own re-rafting instead of migrating it.
- Have order-scan print that line for each refused raft, so step 6 copies it.
- Move the old body into the raft's existing `## Cross-raft waits` (above what it already holds) when it has one, otherwise into a new section directly after the Order.
- In step 6, run the scan as `./zn run --time 120 -- lune run …` (or `./zn check d0295`).
- Add "every raft `order-scan` lists at execution (R0109 on 2026-11-15)" to Touched modules.
- Say that a migrated raft keeps its reviewed order, so it needs no new raft-mode review.

Lesson: zz-arch/records-cover-what-was-reviewed

### F4 [low] The Cross-raft waits template comment, with real-looking ids, is rendered into the prompt of every raft that has no waits
Where: `z-nile/templates/raft/doc.md` (new section); `main.renderPrompt` `CROSS_RAFT`; z-raft §3's new bullet
Evidence: `main.raftSection` returns the section trimmed, comments included. z-raft's new bullet says nothing about a raft with no waits, and `sectionWritten` is not asked about this section. So a raft made from the new template with no waits renders `### Cross-raft waits\n<!-- Orders against other rafts and their issues (this raft merges before R0062; c0264 is done first), written in both rafts' documents. Never read as layers. -->` into `prompt.md`, the executor's brief. That is an example wait on R0062 and c0264, both ids that exist in this repository.
Critique: the tempting fix is to delete the example. That loses the guidance the comment gives z-raft.
Consequences: Theme, Order and Interfaces behave the same way, but z-raft always replaces those; this section will usually be left as the template wrote it.
Recommendation: end z-raft's bullet with "write `None.` when there are none", and use placeholders (`R<NNNN>`, `<issue-id>`) in the template's example instead of live ids. Add an order-docs case that the comment names no `[fdcR]NNNN`. Optionally, have `renderPrompt` drop `<!-- … -->` from `CROSS_RAFT`.

### F5 [low] Wrong labels and a tautology in the sequestered files; "both passes" names a pass that does not exist
Where: `acceptance/order-docs.spec.luau:2`, `experiments/order-scan.luau:2`, `acceptance/order-cli.spec.luau:2` and the case "status <R> prepared takes the same order…"; Design `readycheck.luau` paragraph; AC2
Evidence:
- order-docs' header says AC5 (it is AC4), order-scan's says AC6 (it is AC5), and order-cli's says "AC3, AC4" (it is AC3).
- `t.expect(trackerfix.trOk(f, A, { "stack", R })).toBe(trackerfix.trOk(f, A, { "stack", R }))` compares a command's output with itself; only `trOk`'s own success is checked.
- "before `if not r.loaded`, so both of work next's passes run it" and AC2's "on both of work next's passes": `workread.blockFor` calls `readycheck.reason` once per prepared raft, with `loaded = true` (`workread.luau:444-457`). Its `loaded = false` call (385-398) is only for rafts that are not prepared, and it returns at the first check. The placement is right, but an executor will look for a first pass that does not exist.

Critique: none of this lets a wrong implementation pass, but the sequestered files are frozen after prep, and the labels are what `./zn check` and the trace cite.
Consequences: none.
Recommendation:
- Fix the three headers.
- Make the stack assertion check its rows (`1 {R}/1/c0010`, `2 {R}/2/c0020`).
- Reword to "before `if not r.loaded`, so a caller that has not loaded the design files yet (the `loaded = false` contract) is refused too", and drop "both passes" from AC2, or name the `loaded = false` call.

## Lesson candidates (for the lead)
- zz-test (extend `dry-run-promoted-specs-under-the-guard-scan`): a `check.sh` is scanned by `repo-fence.spec` the moment it is written in prep, not at promotion, so never name a banned name (`GIT_CONFIG_`, `credential.`, `env -i`, …) in one, even to unset it. Why: d0295's `nostep` unset `GIT_CONFIG_*`, and the selector does not pick `repo-fence` for a new `check.sh`. Check: was `tests/tooling/repo-fence.spec.luau` run on the prep tree after the last `check.sh` edit?

Verdict: changes

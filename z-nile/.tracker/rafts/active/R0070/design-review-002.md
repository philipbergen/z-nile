# Review 002: R0070 (design mode, raft mode)
Inputs: branch raft-r0070-fold-c0189 at ce9db1850 (origin/main 2c6197382); R0070.md, R0070/check.sh, design-review-001.md, design-refute-001.md; c0189.md, c0189/check.sh, c0189/acceptance/{wiring,repo-hook,hooks-plan,hooks-command,replace-mode}.spec.luau, c0189/experiments/prototype.patch, c0189/approval.md; c0194.md, c0194/check.sh, c0194/acceptance/{docs,callers}.spec.luau; layer 1 as pushed, origin/R0070/1/c0194 at 628fa478c (its questions.md included); d0298.md; zz-rules (Merging), z-raft lessons (`./zn lessons --skill z-raft`).
Grouped: [c0189@e419f871565a, c0194@ab969aed993b]

Method. I recomputed both `grouped:` hashes from origin/main with `raftplan.recordHash`, and both match (c0189 e419f871565a, c0194 ab969aed993b). I then built the tree layer 2 will really start from, in a clone under this worktree's `.cache` with origin removed. Layer 1 (`origin/R0070/1/c0194`, merge-base 6f328b314, 208 commits behind main) was re-applied onto origin/main 2c6197382; one AGENTS.md hunk conflicted. c0189's `prototype.patch` was then applied with `git apply --3way`. I settled each conflict by keeping both sides, and every spec ran through that tree's own `./zn tmp new unguarded` + `./zn tmp jail` (the procedure in zz-test, as layer 1 states it), bounded by `./zn run`. Results:
- `c0194/callers`: 9/9, `c0189/hooks-plan` 14/14, `c0189/replace-mode` 5/5, `c0055/setup-run` 8/8, `c0172/merge` 17/17, `c0115/docs` and `c0116/docs` pass, `c0131/{accept,refuse}`, `c0077/{replace-file,cache-paths}` pass. The F2 interface of review 001 holds on the real layer 1: no `mktemp` exception is needed.
- `c0189/repo-hook` 16/16 and `c0189/hooks-command` 20/20, but only once the dispatch wrapper was removed from PATH (F2).
- `c0189/wiring`: 8 passed, 4 failed (F1). `c0194/docs`: 1 failed, from my own AGENTS.md resolution of layer 1's restack (layer 1's own text has the pinned sentence). Not a finding.
- `repo-fence`: only the live-jail case fails, as expected in a nested jail.

### F1 [high] c0189's sequestered `wiring.spec` cannot pass on current origin/main: two of its pins name text that main removed after c0189's prototype was cut, so layer 2 stops at a sequestered spec
Where: c0189/acceptance/wiring.spec.luau (cases "the gate's static stage runs ./zn hooks --check beside the skills check, and --plan lists it" at :38, "the usage text and the command table name hooks…" at :83, "the merge's clone installs the hook before its gate" at :94, "the prototype rule reads the same…" at :135); R0070.md Order & dependencies ("settles the four skill conflicts as its E13 lists them"), Risks ("c0189 is executed on top of layer 1 … plus the four skill conflicts (E13)"), Whole-raft design ("The merge's clone").
Evidence:
- c0189's prototype base is 99913e40 (2026-11-01). Applied onto layer 1 restacked on 2c6197382, it conflicts in **9 files, 13 hunks**: AGENTS.md, `z-nile/check.sh` (2), `z-nile/engine/main.luau`, z-design (2), zz-arch, zz-execute, zz-review, zz-rules (2) and zz-test (2). The raft promises four. Applied onto origin/main alone, 8 of those files conflict too, so this is drift on main, not c0194.
- `wiring.spec:38` needs the literal `par_wait || exit 1` after the hooks stage. Main has had none since R0081 (3052ce610, 2026-11-05). The line is now `par_wait >"$report" || { cat "$report"; exit 1; }`, and the skills stage now runs only `[[ $mode == full ]] || picked z-nile`.
- `wiring.spec:94` needs "Spawn the gate there" after "Run `./zn hooks` in the clone". Main's Merging step 2 has not had that sentence since #291 (94fc92b40, 2026-11-10). Step 2 now gates a tooling-only PR with `z-nile/check.sh --affected` on the branch and no clone; only a PR that changes a game gets the clean-clone full gate.
- `wiring.spec:83` needs "`capture <id>` (they only read), `hooks --check` (it only reads), and the worktree commands" with nothing in between. Main inserted "`work`, `work next` and `work status` (…)" there (ebe00b266, 2026-11-13). This one can be met by moving the `work` clause, since no spec pins its place. The same goes for `:135`'s "scratch clone or worktree (the rule under Unknowns & experiments)" beside layer 1's mutation-check wording.
- The raft's evidence for coherence is E13 and E14, run on two prototypes cut on 2026-11-01. c0189's approval (approval.md, 2026-11-19T04:53Z) and this fold (2026-11-18) came after all three of main's changes, and nobody reran it.
Critique: the executor may not edit `wiring.spec`, and the only ways to make `:38` and `:94` pass in the code are to undo landed work (R0081's gate report, #291's tooling/game split) or to add words that exist only to satisfy a pin (a stray `par_wait || exit 1`, a "Spawn the gate there" sentence main deliberately removed). The first is a regression and the second games a pin. Layer 2 is a zz-execute stop condition on its first `./zn check c0189`. The tempting raft-level fix is a sentence telling the executor to "settle the conflicts", which changes nothing about the pins.
Consequences: fixing it changes c0189's design. `wiring.spec`'s gate case and merge-clone case are re-cut against today's `check.sh` and Merging step 2. That brings two design decisions c0189's amendment must make and state:
- Does the hooks stage follow the skills stage's new condition (`full` or z-nile picked)? If so, a game-only `--affected` run skips it and only `--full` and z-nile changes check the hook.
- `./zn hooks` in a clone now applies only to the game-PR clone. A tooling PR's merge gate runs in the raft worktree and reads the real repository's hook, so after this raft merges, every tooling merge is red until the main checkout runs `./zn hooks`. Risks' "After the merge" step becomes a step that blocks the next merge, not a courtesy.
The re-cut changes c0189's contract, so its approval of 2026-11-18 must be given again. Its `grouped:` hash changes, so this raft needs a new fold and a new coherence round.
Recommendation: z-raft takes c0189 out of R0070 (`./zn unfold R0070 c0189`, per raft mode: the fix needs a member's design to change). In c0189's prep (z-design, an amendment round with its review):
1. Re-cut `wiring.spec`'s gate and merge-clone cases against origin/main as it is then, and decide the two questions above in its Design.
2. Re-base `experiments/prototype.patch` on `origin/R0070/1/c0194` restacked onto origin/main.
3. Rerun every c0189 spec and its mutation rows there, plus `c0194/callers` and `c0194/docs`, and record the run as a new E-number.
4. Get the human's approval again.
Then z-raft folds c0189 back into R0070, which is the user's 2026-11-17 request ("A and can you fold it into r70"). The fold keeps the request and only puts it after the fix; nothing is cut. The new raft record replaces "four skill conflicts" with the conflict list the re-based run actually meets (none, if the prototype is cut on the restacked layer 1) and needs one coherence round. Layer 1 can carry on alone in the meantime: nothing in c0194 waits for c0189.
Lesson: z-raft/prototype-stack-holds-final-tips
Erred: z-raft
Upstream: z-design

### F2 [medium] Under `./zn dispatch`, six of c0189's hook cases fail on the dispatch git wrapper until d0298 (R0096) lands; the raft does not order against it
Where: R0070.md Order & dependencies (it orders against R0039, R0078, R0073 and R0131, not R0096); c0189/acceptance/hooks-command.spec.luau (5 cases), repo-hook.spec.luau:315 (1 case); `z-nile/bin/git`; d0298.md Design (`fence.STEP_VARS`, `fence.stepPath`).
Evidence: in this dispatched session, on the stacked tree, `hooks-command` gave 15 passed, 5 failed and `repo-hook` 15 passed, 1 failed. The failing cases push a non-tracker file to their fixture's `main` (`tests/lib/trackerfix:109`, `git push -q origin HEAD:main`), and the step's wrapper (`z-nile/bin/git` → `wrap.luau`, first on PATH under dispatch) refuses that push: "git (z-nile wrapper): git push to main refused: z-nile/lib/repo-hooks/reference-transaction is not tracker state … (open a pull request; only ./zn publishes to main)". The other cases fail on what follows from the refused push. With `z-nile/bin` removed from PATH, the same specs pass 16/16 and 20/20. d0298 (raft R0096, `active`) is the change that makes the spec runner drop `z-nile/bin` from PATH and unset `ZN_REAL_GIT` for every spec process. Until it merges, layer 2's `./zn check c0189` and `./zn finish c0189` are red in any dispatched run step, which is exactly how this raft is being run.
Critique: the executor will see a red that looks like c0189's own defect and may "fix" the spec fixture or the hook. The tempting raft fix, "run layer 2 interactively", only moves the trap to the next dispatched run.
Consequences: an order against R0096 that z-ready does not enforce (R0096 is a raft, not a member's `depends_on`), the same gap review 001 F3 found for R0039. If R0096 lands first, nothing else is needed. If it does not, a dispatched layer 2 must stop with this cause named.
Recommendation: add to Order & dependencies: "Layer 2 (c0189) waits for R0096 (d0298) under `./zn dispatch`: until it merges, the dispatch wrapper refuses the fixture pushes in `hooks-command.spec` and `repo-hook.spec`; an interactive `./zn work` run is not affected." Name the wait in the layer-2 step of the raft prompt, and tell the executor that this red is a stop that names R0096, never a reason to edit the fixture. Check `./zn find R0096` before layer 2 starts.
Lesson: z-raft/cross-raft-wait-bites-at-the-first-red-layer
Erred: z-raft
Upstream: none

### F3 [medium] c0194's step-8 note under c0189.md would break c0189's approval inside the same raft, and c0189.md still says it is rafted only after R0070 is done
Where: c0194.md Implementation step 8 and Existing work ("adds a dated note under each draft's captured text … they stay drafts"); c0189.md:134 ("R0070's step 8 adds a dated note under this document … and stays. Because it edits this document, **this chore is rafted only after R0070 is done**"); R0070.md Risks ("Dated notes in a member document … If a check or `./zn done` refuses it as a changed member, take the note out").
Evidence: c0189 is approved (approval.md on origin/main, 2026-11-19T04:53Z, `design=4dae4044…`). The approval contract hashes the Problem, Solution, Design, Acceptance criteria and Test plan sections (`z-nile/engine/contract.luau`, `contract.HEADS`). c0194's note goes "under each draft's captured text", which for c0189 is its Problem. Once the note is added, `./zn done R0070` refuses "a changed contract" (zz-execute Phase 5 step 5) until the human runs `./zn approve c0189` again, and an unattended run stops at `wait`. The note's premise is false: c0189 is not a draft, and its rule already names `.cache/.tmp/` (c0189.md:115). The raft already skips the c0157 half of the same step for the same kind of reason, but leaves the c0189 half as a "take it out if refused" fallback. c0189.md:134's "rafted only after R0070 is done" contradicts this fold, and no line marks it as overtaken by the user's ruling.
Critique: the refusal is certain, not conditional, and it costs a round trip to the human at `done`. An executor reading c0189.md gets two contradictory placement rules for its own raft.
Consequences: skipping the note leaves c0194's captured outcome intact ("c0189's 'scratch clone' wording points there too" is met by c0189:115, and `wiring.spec` pins it). c0189.md needs one line beside its :134 sentence, which changes its design hash. That lands in the same amendment as F1 (c0189 is unfolded and re-approved anyway), so it adds no extra round.
Recommendation: in R0070.md Whole-raft design, "To c0157 and c0123", make the c0189 half explicit: the executor skips step 8's note under c0189.md (c0189 is a member, approved, and already states the definition), and reports it. Remove the conditional Risks bullet. In c0189's F1 amendment, mark :134's "rafted only after R0070 is done" and "R0070 contains c0194 and is readied" as superseded by "A and can you fold it into r70" (user, 2026-11-17), with the reason: the note is skipped, so neither the grouped hash nor the approval moves.
Lesson: z-design/restated-rules-move-together
Erred: z-raft
Upstream: z-design

### F4 [low] Several facts in R0070.md are stale against the tree
Where: R0070.md Whole-raft design (`repo-fence.spec.luau` bullet; "The merge's clone"), Order & dependencies, Risks.
Evidence:
- "G1 (pending the user) is about c0189's part", while Risks says G1 was decided on 2026-11-17 (c0189.md:330).
- "c0189 … has none [approval] on record today", but approval.md is on origin/main (2026-11-19T04:53Z).
- "R0078 is `active` … #463 is open and unmerged". R0078 is in `done/`; #463 merged 2026-11-19T05:19Z.
- "R0131 (d0297, active, #604 open) … is not ordered against this raft". #604 merged 2026-11-18, and d0297 was layer 1's blocker: `origin/R0070/1/c0194` carries `rafts/active/R0070/questions.md`, "d0297 blocks finish", which nobody has answered and is now resolved. The raft does not tell the executor resuming layer 1 that.
- The "merge's clone" bullet describes one clone sequence for every merge. Main now clones only for a game PR (see F1).
Critique: an executor trusts these lines when deciding what to wait for.
Consequences: none beyond the edits.
Recommendation: correct each line in the same rafting change. Add to the layer-1 step that its `questions.md` is answered by d0297's landing (option 1, which it recommends), so the executor restacks, reruns `./zn finish c0194` and removes or answers that file.
Lesson: z-raft/copied-raft-text-is-reverified
Erred: z-raft
Upstream: none

Verdict: changes

# Review 002: c0247 (design mode)
Inputs: worktree `prep-ticket-confirms-intent` at 338d986d plus its uncommitted `c0247.md`, `check.sh`, `acceptance/docs.spec.luau`, `design-refute-001.md`, `harvest.md`, the new lesson `zz-test/no-change-claims-check-behaviour-not-the-raft-diff`; `proto247.patch` applied in a scratch clone (`scratchpad/rv2`, commit 31b64b08, `origin/main` = d9bd5c7b, merge base 338d986d) with a temporary `z-nile/tests/inputs.tsv`; mutants in a second clone (`rv3`); the prototype on top of `impl-c0117` 6878dd0a (`rv4`); c0117's active document and `acceptance/docs.spec.luau`; c0256 on origin/main (d5f8930f) and its unlanded capture commit ee8bf541 (`capture-dispatch-retry-passes-answer`); `./zn capture c0247` (53ad228c, no marker).
Dropped from review-001: none. Round-1 fixes re-run and holding: F2 (AC7 replaces the branch diff; c0239's and c0160's Overrides cannot redden AC6 or AC7, see below), F3, F5, F6, F7, F8, F9. F1 holds only in part (F1 below); F4's E2 half is repeated (F4 below).

Re-run evidence: `./zn check c0247` on the prototype: 7/7. AC6 mutant (step 5's label renamed to `**Duplicate check**`): AC6 FAIL, 6/7. c0117's `docs.spec` on `impl-c0117` plus the prototype: 9 passed, 0 failed (both z-ticket edits apply cleanly and coexist). The promoted corpus-scanning specs on the prototype (c0115 `absence`, `layout`, `skills`, c0111 `skill-docs`, c0184 `skills`): 39 passed, 0 failed. The whole promoted z-nile suite (172 files) did not finish inside a 590 s `./zn run` limit, so running all of it is not an option for AC7 (F3).

AC6 and AC7 with raft mates' Overrides: c0239's six Overrides and c0160's two (`c0120/checkpaths.luau`, `c0120/rewrites.luau`) touch no z-ticket step heading, so AC6 (headings against the merge base) stays green. AC7 runs the reader specs as they are on the branch, so a raft mate's override of `c0114/docs` is judged by what it says, not by a diff. Neither check can go red for a correct c0247 because of a raft mate's Overrides. c0181, the only in-flight item that edits z-ticket step text, is `solo: true`, so it never shares a raft with c0247.

Capture comparison: the title, Problem and three Solution bullets are as captured. The two `Decided with the user` lines are the only additions to the Problem. Every captured outcome has a Design and a Checked criterion (plan mode has OC1 as well). No narrowing.

### F1 [high] Once the user has approved, a re-run z-ticket under the dispatcher (or a freshly briefed subagent) has no rule that accepts the approval. It restates again and stops again, so no dispatched capture is ever made.
Where: pinned paragraph, "A restatement the user has already approved in this conversation counts." and "under `./zn dispatch`, write it as the question in `questions.md` and stop"; Problem, decision line F1 ("the user's approval or correction reaches the re-run step through `dispatch retry`, which c0256 … provides"); Decisions and limits, "Nothing is created before approval, not even the worktree"
Evidence:
- `dispatch retry` starts a new headless CLI session. The re-run z-ticket reads the paragraph, and the only rule that lets it go ahead is an approval "in this conversation", which a new session doesn't have. Wherever c0256 puts the answer (the prompt, a file), the skill never tells z-ticket that this answer is the approval. It restates and writes `questions.md` again, and the loop never ends.
- c0256 assigns the rule back to c0247 explicitly. Its Non-goal (ee8bf541): "The wording of z-ticket's confirmation is c0247's. This chore only gives a retried step the user's answer."
- A subagent the lead launches again after the user approves has the same gap: the approval is in its brief, not in "this conversation".
- The surrounding path is less ready than "c0256 provides" suggests. Read in `impl-c0117` (`z-nile/engine/dispatcher.luau`):
  - line 809: the dispatcher creates `.worktree/capture-zn-<time>` before z-ticket starts, so a restatement stop leaves a worktree behind, and each retry makes another. "Not even the worktree" is false on this path.
  - lines 1098–1106: a z-ticket that stops with questions made no issue, so its attempt is recorded `failed`, "z-ticket made 0 issues on origin/main, not one". `next()` still stops with exit 3, because it checks questions first.
  - `dispatch.luau:290`: a `new` run's stop message is "`./zn dispatch retry `" with `f.id = ""`.
  - line 1779: `--description` is read only from the current command's options, so `retry` re-runs the chain with no description and stops with "` is not on origin/main`".
- origin/main's c0256 still has `depends_on: []`. The `[c0117]` that the Design quotes is in the unlanded capture commit ee8bf541.
Critique: the user's decision says the answer reaches the re-run step. c0247 owns the words the re-run step follows and doesn't write the one sentence that makes the step act on the answer. This is lesson z-design/results-land-on-every-path's "Inputs too": the dispatched path has no carrier for the approval. The tempting fix is "under the dispatcher, skip the confirmation on a retry". That files the ticket even when the answer was a correction.
Consequences: the sentence has to work with whatever c0256 designs, and c0256 isn't designed yet. So it should name the answer by what it is ("the user's answer the dispatcher hands you on a retry"), not by a file name. A correction in that answer means one more restatement and one more stop, which is consistent with "A correction means you restate again". The leftover `capture-zn-*` worktree, the `failed` attempt row, the empty retry id and the missing description all belong to c0256 or c0117, but c0247's claim that c0256 "provides" the path holds only if c0256's scope names them.
Recommendation:
- Add to the paragraph, pinned in AC2, with a mutant row (the sentence removed, or "in this conversation" left as the only approval) that AC2 kills: "Under `./zn dispatch`, the user's answer to that question, which the dispatcher hands you when the run is retried, is their reply: an approval is the go-ahead, a correction means you restate again. A subagent whose brief says the user approved the restatement goes ahead."
- Qualify "not even the worktree" in Decisions: under the dispatcher, the dispatcher's own `capture-zn-*` worktree exists before the step starts.
- In Existing work, list what c0256 must cover for c0247's path: a `new` run keeps its words and a retry handle, a stopped z-ticket's worktree is reused or removed, and a z-ticket that stopped with questions isn't recorded as a failure.
- Land the c0256 capture commit (ee8bf541, `depends_on: [c0117]`) before this prep merges, and add those three points to c0256's Problem as detail (z-design: detail may be added).
Lesson: z-design/results-land-on-every-path

### F2 [high] AC5 passes when the `inputs.tsv` declaration is dead: the spec matches a substring, and the Design spells the spec path without its `tests/` prefix.
Where: `acceptance/docs.spec.luau` AC5 (`string.find(tsv, "acceptance/c0247/docs.spec.luau\t{path}", 1, true)`); Implementation step 3 ("Append the two `acceptance/c0247/docs.spec.luau` lines … format `<spec relative to the home><TAB><input>`"); Affected specs
Evidence:
- c0165's file and parser (`origin/R0081-reuse-test-results`) key a line by `homePrefix .. spec`. The header line reads `<spec, relative to the home>`, and every row is spelled `tests/acceptance/<id>/<name>.spec.luau`. `sel.parseInputs` checks only that the path ends `.spec.luau`. It never checks that the spec exists.
- So the rows the Design and the spec ask for, `acceptance/c0247/docs.spec.luau<TAB>z-nile/skills/z-ticket/SKILL.md` and the same for the README, are keyed `z-nile/acceptance/c0247/docs.spec.luau`, a spec that doesn't exist. I ran exactly those two rows in `rv2`: `./zn check c0247` passed 7/7, AC5 included.
- The correct row, `tests/acceptance/c0247/docs.spec.luau<TAB>…`, also matches the substring. AC5 can't tell the dead form from the live one.
Critique: the declaration is the whole point of AC5 (lesson z-design/declare-what-full-runs-covered). A dead declaration means that, under c0165's selection and result reuse, an edit to z-ticket's `SKILL.md` or the README doesn't change the promoted c0247 spec's fingerprint. The spec is then skipped or its old pass reused, and the rule it pins goes unchecked. The tempting fix, a longer substring with `tests/` in front, is still a second hand-written reader of a format that has one.
Consequences: reading the file through c0165's own parser ties AC5 to c0165's format. c0247 already `depends_on: [c0165]`, so the parser exists when this is built. If c0165 changes the format, AC5 follows it.
Recommendation:
- Spell the row `tests/acceptance/c0247/docs.spec.luau<TAB><input>` in Implementation step 3 and Affected specs.
- In AC5, parse `z-nile/tests/inputs.tsv` with `select.parseInputs(text, "z-nile/", roots)`, require no error, and require that key `z-nile/tests/acceptance/c0247/docs.spec.luau` holds both inputs. If the spec can't require `z-nile/lib/select.luau`, anchor the match to a whole line: split on `\n` and compare each line exactly.
- Add mutant row M19, the two rows written as `acceptance/c0247/…`, which AC5 must kill. Run it.
Lesson: zz-arch/one-reader-per-format

### F3 [medium] AC7's reader list is a grep for two literal paths, so it misses the promoted specs that scan the whole corpus. A c0247 edit that reddens one of them passes AC7.
Where: `check.sh` AC7 (`git grep -lF -e 'z-ticket/SKILL.md' -e 'z-nile/README.md' -- 'z-nile/tests/acceptance/*.spec.luau'`); Affected specs ("the eight promoted specs that read the two files"); Regression guard; the new lesson's How to apply ("with the reader list computed by `git grep -lF`")
Evidence:
- The search, rerun in `rv2`: `git grep -nE 'skills/\{|/SKILL\.md`|README' -- 'z-nile/tests/acceptance/*.spec.luau'`. It finds specs that read every skill through a loop or a scan, which the literal grep can't see:
  - `c0115/absence` scans every tracked text for old skill names;
  - `c0115/layout` reads `z-nile/skills/{name}/SKILL.md`;
  - `c0111/skill-docs` reads `{dir}/SKILL.md` for every skill;
  - `c0184/skills` and `c0115/skills` read every skill.
- Mutant in `rv3`: append "This replaces the confirmation make-issue never had." to the paragraph. `./zn check c0247` passes 7/7, AC7 included. `lune run tests/run -- tests/acceptance/c0115/absence.spec.luau` fails: "old skill names: z-nile/skills/z-ticket/SKILL.md: make-issue at line 8".
- Without the mutant, those five specs pass on the prototype (39/0), so no Override is missing today. The gap is in the check.
Critique: AC7 promises that the promoted specs reading these files still pass, and a wrong edit passes it. `done`'s full gate is the backstop, so nothing wrong can land, which is why this is medium and not high. The new lesson goes further and teaches every later raft the same incomplete grep (lesson zz-review/lists-paste-their-search, c0153 note: the pattern must cover every spelling). The tempting fixes don't hold up:
- Run every promoted z-nile spec: that took longer than 590 s here.
- Paste the five extra specs into the list by hand: the list goes stale the next time a scanner is added.
Consequences: c0165 (a dependency) makes `inputs.tsv` the record of which spec reads which file, with `*` for corpus-scanning and registry-driven specs. Its `isInput` is the one predicate for "does spec S read path p". If AC7 is derived from it, AC7 stays right as scanners are added, and its run is the set the gate itself would run.
Recommendation:
- Compute AC7's list as every promoted `z-nile/tests/acceptance/**/*.spec.luau` for which c0165's selector says one of the two files is an input: `select.isInput`, or `lune run z-nile/affected -- <the two files>` once it no longer prints `ALL` for them. Take the union with the literal-path grep, for readers that are not yet declared.
- Paste that list and its command into the Regression guard.
- Add mutant row M20 (an old skill name in the paragraph) and require AC7 to fail on it. Run it.
- Rewrite the new lesson's How to apply to say the reader list comes from the selector's declared inputs, not from a literal-path grep, and cite this mutant.
Lesson: zz-review/lists-paste-their-search

### F4 [medium] (repeat of review-001 F4, its E2 half) What plan mode's dialogs do to a capture is still unprobed, and the paragraph has no branch for two outcomes they can produce.
Where: E2 ("Not probed from the prep lead's session, because entering plan mode here would stop the design"); pinned AC2 sentence; Decisions ("It costs one round trip per message"); OC1
Evidence:
- The refutation's reason doesn't hold. Plan mode stops the session only until the user answers one dialog, and the user is present: the two decisions in the Problem were made today, in this prep. A throwaway Claude Code session in a scratch folder would also do.
- The paragraph and the "one round trip" claim depend on harness behaviour nobody has recorded:
  - whether `EnterPlanMode` asks the user's consent first. If it does, that is a second round trip, and a "no" falls under no branch: "Without it" means the tool isn't offered, not that the user declined.
  - what the `ExitPlanMode` approval choices do to the session. Choices that switch to auto-accept edits change the permission mode for the rest of the session, including later work in the main checkout. A choice that clears the context drops the z-ticket skill text, so the agent wakes with only the plan and doesn't know steps 0 to 6 follow.
- As a subagent, I can't load either tool to probe it (`ToolSearch` found neither, as in round 1), so only the lead or the user can run this.
Critique: lesson z-design/instructions-runnable-where-they-run. The one mechanism the user asked for is the one part of the rule nobody has run. Leaving it to OC1, after the raft is built, means a bad dialog flow ships in a promoted, pinned sentence.
Consequences: the paragraph may need two short additions, which change the pinned AC2 text and its mutants: "if the user declines plan mode, print the restatement and stop", and "end the plan with 'then capture it with the z-ticket skill, steps 0 to 6'". OC1 should then check the permission mode after approval.
Recommendation:
- Run E2 once: enter plan mode, decline once, correct once, approve once. Record each dialog and its choices, which choice keeps the permission mode, and what a context-clearing choice leaves.
- Write into the paragraph the branches the run shows are needed (at least the declined-plan-mode branch and the plan's last line), pin them in AC2 with mutant rows, and add those checks to OC1.
- If it really can't be run before the merge, escalate to the user: (a) let the lead run E2 now (one short pause); (b) keep it Observed and accept that the pinned wording may need an Override chore later.
Lesson: z-design/instructions-runnable-where-they-run

### F5 [low] Small inconsistencies in the document
Where: Decisions and limits; Existing work; Rules and mutants
Evidence:
- The Decisions bullet glosses "already approved" as "(they said yes to a proposed capture)". Review 001 F3 said that is a yes to filing, not to a restatement, and the answer didn't address it. The pinned skill sentence is fine; the Design text contradicts it.
- Existing work points to "the lesson candidate below", but nothing below it is one; the lesson became a file.
- Existing work says c0256 has "`depends_on: [c0117]`"; on origin/main it is `[]` (F1).
- Rules and mutants has no row for three pinned rules, though the verbatim pins already kill their mutants: "skip it when you are already in plan mode", "a subagent returns the restatement to its lead", and "with any overlap `./zn list backlog` shows".
Recommendation:
- Change the gloss to "they approved that restatement".
- Drop or fix the dangling reference.
- Fix the dependency once ee8bf541 lands.
- Add the three rows (mark them `run` once they've been run on the prototype).

Lessons pass (`./zn lessons --when design`): z-design/results-land-on-every-path (F1, "Inputs too"); zz-arch/one-reader-per-format (F2); zz-review/lists-paste-their-search (F3); z-design/instructions-runnable-where-they-run (F4); z-design/quote-other-preps-before-promising (F1: c0256's dependency, and its Non-goal handing the z-ticket wording back to c0247); z-design/run-the-other-rafts-specs (satisfied: c0117's `docs.spec` passes 9/9 with both prototypes). Harvest: the new lesson `zz-test/no-change-claims-check-behaviour-not-the-raft-diff` is a real lesson another raft could fail, not a restated finding, but its How to apply prescribes the incomplete literal-path grep (F3).

Candidate lesson (for the lead to file): zz-test: a check that "the spec's inputs are declared" must parse the declaration file with its own parser and look up the exact key, because a substring match accepts a row whose spec path doesn't exist, and the parser never checks that it does (c0247 design review 002 F2). Check: would a row with the wrong path prefix still pass this check?

Verdict: changes

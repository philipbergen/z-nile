# Review 001: c0306 (design mode)
Inputs: prep worktree prep-refuse-reviews-on-cheap-models at 769e0e11c plus its uncommitted files (c0306.md, check.sh, acceptance/*.spec.luau, experiments/prototype.patch, harvest.md, idea-review-001.md, idea-refute-001.md); origin/main 3cadd2cef; prototype proto-c0306 a70b41a6 (base 2569d66e), read only; `./zn capture c0306` (capture 47201096, no marker). `./zn check c0306` on the prototype: 10/10 criteria pass, and the runner's tripwire did not fire.

### F1 [high] In every marked item, the spend that records the author's answering time is refused, which breaks z-design step 4 and z-raft's coherence round
Where: c0306.md Design outcome 3, bullets 3 and 5; prototype `z-nile/engine/main.luau:6410` (`cmd.spend`); `z-nile/skills/z-design/SKILL.md:66`, `z-nile/skills/z-raft/SKILL.md:42`, `z-nile/skills/zz-rules/SKILL.md:132`
Evidence: Outcome 3 says "`./zn spend --phase design-review` (not `--begin`) is refused without `--model` ... and without `--note design-review-NNN`". Its last bullet says "A refute (`design-refute-NNN` ...) is the author's, so no flag is required for it". Both cannot hold, and the prototype implements the first. In an item marked `reviews: judged`, the following happens:
- `./zn spend <id> --phase design-review --note design-refute-001` (z-design step 4, "Once the round is answered") fails with "needs --model".
- The same line with `--model` fails with "needs --note design-review-NNN".
- z-raft's "`./zn spend <R-id> --phase design-review` when you stop" fails the same way, and so does zz-rules' "and again for the answering time".
After c0306 lands, every prep and every multi-issue rafting is marked, so this hits every one of them. No case covers it: `commands.spec.luau:363` writes a `design-refute-001.md` but never spends on it.
Critique: The protocol's own recording step fails on the first prep after landing. The tempting fix is to tell leads to pass `--model <their own id> --note design-review-NNN`. That fails as well: it tries to stamp a review that is already stamped ("recorded once"), and it would record the author's span under the reviewer's file.
Consequences: Dropping the `--note design-review-NNN` requirement means a lead who forgets the note can record a reviewer's run as an answering span. That omission is still caught where it matters, because the review file is then unstamped and `status prepared`/`ready` refuse it with the "record it" way out. A `--model` typed on a refute span would put the author's measured span under the reviewer's model.
Recommendation: In a marked item, require `--model` only when `--note` names a `design-review-NNN` file. A `design-refute-NNN` note, or no note at all (the answering span after `--begin`), records exactly as today with the measured model and stamps nothing. Decide whether `--model` on a refute note is refused or ignored, and say which. Restate AC8 and the zz-rules `spend` row accordingly. Add these cases in a marked item:
- `spend --phase design-review --note design-refute-001` passes and stamps nothing;
- `spend <R-id> --phase design-review` after `--begin` passes;
- `--note design-review-001` without `--model` is refused, as now.
Add the rows for each case, and mutants such as "the refute note is refused" and "any note needs --model".

### F2 [high] The refusals' only way out for an off-model review can never clear them: every round is judged, a record is written once, and a second round of a kind is refused
Where: c0306.md outcome 5 ("Every round is judged, not only the last"; the ways out, "always: run the round again ... `./zn dispatch zz-review <id> --mode ...`"), outcome 2 ("a review is recorded once; run a new round"); prototype `z-nile/engine/dispatcher.luau:1115-1131`; zz-review "Output file" ("A second review of the same kind is refused")
Evidence: Take a marked issue whose `design-review-001.md` records `claude-sonnet-5-5`. `status prepared` refuses it and names `./zn dispatch zz-review c0139 --mode design` (asserted by `commands.spec.luau:344-347`). None of the ways out works:
- The dispatcher refuses that command, because `lastRound` finds `design-review-001.md` ("one round, then the author answers it; there is no second round").
- A fresh subagent is told by zz-review that a second review of the same kind is refused.
- If a `design-review-002.md` on Opus is written anyway, `status prepared` still refuses, naming 001. The AC4 case "judges every round" pins exactly this (`commands.spec.luau:360-367`: 001 SONNET, 002 OPUS, refused).
- The record cannot be corrected: `stamp` refuses a file that already has a `Model:` line.
`done` is worse. Its only way out is "run the round again ... and commit it". Code mode's dispatcher refuses whenever any `review-NNN.md` exists in the raft folder, and the old file stays judged. The specs never follow a way out to a pass. They clear each refusal by rewriting the off-model file in place, which the protocol forbids ("Never edit a review once it is written"):
- `done.spec.luau:415-425` rewrites `review-001.md` and `review-002.md` with an Opus record;
- `ready.spec.luau:178-188` only swaps fixtures.
Critique: A marked item with one off-model review is stuck for good, unless someone deletes or edits a review file by hand. The refusal text then sends the lead to a command that refuses. F6 below makes this reachable from an ordinary dispatcher fallback.
Consequences: Any fix needs an exception to the one-round rule. (a) Replacing the round: the off-model file is removed and the new round takes its number. The dispatcher must then accept that number, which it does not do in code mode, where a later layer's `review-002.md` keeps `last >= 1`. It also changes `./zn metrics`' round counts. (b) Superseding it: a later on-model round of the same kind clears an earlier one. That works for a design or coherence folder (judge the newest round), but a code review needs to know which layer it covers (c0248's `Commit:`/`Patch:`). Either way, zz-review's "a second review of the same kind is refused" and the dispatcher's "there is no second round" change.
Recommendation: escalate to the user: which exception to the one-round rule a review refused by this rule gets. The options are (a) replace the round in place (remove the file, re-run at the same number, and have the dispatcher accept it in every mode), (b) let a later on-model round supersede it (newest round for design and coherence; by covered layer for code), or (c) none, in which case the refusal must say the item is stuck and who unblocks it. Then make each refusal name only steps that work. Add one case per judging command (`status prepared`, `ready`, `work next`, `done`) that follows the refusal's text literally (the dispatch command it prints, and the subagent route) and then passes, plus a dispatcher case that files the replacement or superseding round. Add rows for each.

### F3 [high] Other items' sequestered specs claim through the real commands with unstamped reviews and turn red the day c0306 lands; the search is deferred to execution
Where: c0306.md outcome 9 (c0161 bullet), Implementation step 9; origin/main `z-nile/.tracker/issues/active/c0161/acceptance/review-gate.spec.luau:51,99-102`; `z-nile/.tracker/issues/c0316/acceptance/gates.spec.luau:77,238-249`
Evidence: c0161 (active, R0080) `review-gate.spec`:
- `claimed()` runs `trOk({ "status", id, "preparing" })` on a new issue with no design review. Under c0306 that writes `reviews: judged`.
- It writes `design-review-001.md` as `round("001", "approve", record(id))`, which has no `Model:` line.
- It expects `trOk({ "status", id, "prepared" })` at line 102. c0306's judge refuses that move ("records no `Model:` line").

c0316's `gates.spec` (`prepIssue` claims, then `review("design")` with no `Model:`, then `prepared(id)` is expected ok at 247) fails the same way. Outcome 9 covers c0161 only as "whichever lands second calls both", which is about the reader, not about these specs. Step 9 searches "every open prep's" specs at execution and "tells each owning prep". An active raft's sequestered specs cannot be edited by its executor (zz-execute), and telling it does not make them green.
Critique: If c0306 lands first, R0080's own check.sh goes red mid-raft and its executor must stop. If R0080 lands first, `tests/acceptance/c0161/review-gate.spec.luau` becomes an override of c0306 that its Overrides line does not name. The tempting fix, "tell R0080", leaves both outcomes open.
Consequences: Ordering R0080 first (`depends_on: [c0161]`) delays c0306, and with it c0251, c0175 and c0248, which wait for it. Landing c0306 first blocks R0080 until a chore or the user rules.
Recommendation: Run the search now, not at execution, over origin/main's sequestered specs outside `done/` and every `.worktree/prep-*`. Look for fixtures that claim with `status <id> preparing` or make a raft with `new raft`, then reach `status prepared`, `ready`, `work next`, `done`, `spend --phase design-review` or `commit` with a hand-written review. For c0161, the clean option is `depends_on: [c0161]` with `tests/acceptance/c0161/review-gate.spec.luau` (and any other c0161 hit) named on c0306's Overrides line, with the edit each needs. If the order should go the other way, that is for the user or R0080's lead to rule, recorded with a `Decided` line. Record c0316 and every other hit on c0323 and in the Design, and tell those preps now. Replace step 9 with the recorded list. (Lesson below.)
Lesson: z-design/quote-other-preps-before-promising

### F4 [medium] The eleven overridden specs are all in the slow tier: nothing Checked runs them, their edits were never made on the prototype, and the edit the design states for one of them cannot work
Where: c0306.md Regression guard (Overrides line), E3, Implementation step 10; check.sh AC10 (`fastSpecs` drops every slow spec); `z-nile/tests/slow.tsv`; `tests/acceptance/c0084/spend-command.spec.luau:218-231`
Evidence: All eleven are in `slow.tsv`, about 920 s in total (`c0116/claims` alone is 451 s). `--full` and the net leave the slow tier out (zz-test: "not part of the affected or full gates"), and E3 shows `--full` passing on a prototype that still holds all 38 red cases. So a delivery that never edits them passes every AC and the merge gate. Main's slow tier already carries 8 tolerated reds (E3), so 11 more would go unnoticed too. The prototype contains none of the "about 60 lines". The bullet for `c0084/spend-command` says the fix is `--model claude-opus-5-5` on its design-review spend. That spend names `--note design-review-001` for a raft folder that holds no such file (the spec writes none), so with `--model` the prototype's `reviewfiles.stampFile` fails "does not exist".
Critique: The Overrides list was confirmed by a suite run, which is good. The edits that close it are guarded only by a manual step, and at least one of them is wrong as written.
Consequences: A check.sh line that runs the eleven by name costs about 920 s at finish and done (lesson zz-test/check-sh-never-runs-the-slow-tier). A text proxy is cheap but weaker.
Recommendation: Make the eleven edits on the prototype now and run them once with `z-nile/check.sh --slow -- <the eleven paths>`. Record the result in E3, and correct each bullet (spend-command needs the review file written, or a different spend). For check.sh, either give the eleven a one-time check.sh-only line with its time in a comment (lesson z-design/guards-name-slow-tier-specs), or add a fast proxy criterion that each named file carries the record it needs. Also require the Verification log to quote the `--slow` result for those paths.
Lesson: z-design/guards-name-slow-tier-specs

### F5 [medium] `--effort` defaults to the lead's `CLAUDE_EFFORT`, the same trap outcome 3 removes for the model
Where: c0306.md outcome 2 ("`Effort:` comes from `--effort`, else `CLAUDE_EFFORT`"), outcome 3; prototype `reviewfiles.effortOption`
Evidence: Effort is judged only for `grok-`, and a grok review never runs as a Claude Code subagent. So `CLAUDE_EFFORT` is never the effort of the one kind where effort counts: it is the lead's session's. Suppose a lead in a Claude Code session at `xhigh` records a grok-4.7 review that ran at `high` and forgets `--effort`, typing `./zn commit ... --phase code-review --model grok-4.7`. The record is then `Effort: xhigh`, and `done` passes it. Outcome 3's own rationale is that defaults must not "silently record the author's own model instead". The honour system judges what the lead types, and here the effort was not typed.
Critique: The rule guards against forgetting, and this default turns exactly that slip into a pass. For the other three kinds it only writes a possibly wrong informational line.
Consequences: Requiring `--effort` for `grok-` adds one refusal at `spend` and `commit`. Dropping the default entirely leaves `Effort:` out more often, which is harmless for the other kinds.
Recommendation: Never take the effort from the environment for a `grok-` model. Refuse `--model grok-…` without a typed `--effort` at `spend` and `commit`, or drop the `CLAUDE_EFFORT` default altogether. Add a case: with `CLAUDE_EFFORT=xhigh` and `--model grok-4.7` and no `--effort`, the call is refused (or records no `Effort:`, and the judge then refuses). Add the matching row.

### F6 [medium] The roles table produces reviews this rule refuses: a raft-mode review that falls back to grok runs at `high`
Where: `.models.toml` `[roles.raft]` (`effort = "high"`, `fallbacks = ["kimi", "grok", "agent"]`; "A try is the role's rank, cap and effort on that model"); c0306.md Non-goals (no `.models.toml` change), outcome 2 (dispatcher stamp)
Evidence: When the claude CLI and kimi both fail (quota, stall), `./zn dispatch zz-review <R> --mode raft` tries `grok-4.7` at the raft role's `high`. The dispatcher files and stamps it `Model: grok-4.7`, `Effort: high`, and `ready` refuses it, since `ok` is false. With F2, the raft cannot then be readied at all. The Design never says that some try of a review role is off the review models.
Critique: The dispatcher spends a full review run whose result is refused by construction, then strands the item.
Consequences: Skipping such tries can leave a review step with no try at all. The step must then fail up front with a clear message.
Recommendation: In a review step (every mode but stream), the dispatcher skips any try whose `(spec.model, spec.effort)` `reviewmodel.ok` refuses, and fails the step "no try of role <r> is a review model" when none is left. Add a `dispatch-review` case where a grok fallback at `high` is never started and the next try is, and the matching row. If the user prefers changing `[roles.raft].effort`, that is against the Non-goal, so escalate to the user.

### F7 [low] The mark has two readers that can disagree, and the claimed "unreadable front matter is refused" guard does not exist
Where: c0306.md chore checklist, Guards ("an unreadable front matter [is] refused"); prototype `publish.luau` `hasMark`/`withoutMark` (exact text `\nreviews: judged\n`) vs `store.readFront` + `reviewmodel.judged` (trimmed key/value); `ledger.isModel` widening
Evidence:
- `store.readFront` returns `{}` for a document with no front-matter block, so `judged` is false and the item is exempt: it fails open. No case covers it.
- `reviews: judged ` (a trailing space) is judged by the commands, but publish's guard does not see it.
- zz-arch rule 5 asks for one reader per format.
- Separately, widening `ledger.isModel` also widens `.models.toml` validation (`models.luau:237`), which the Design does not state.
Recommendation: Have publish read the mark through `reviewmodel.judged` over the parsed front matter, or have both use one helper. Either drop the "unreadable front matter is refused" claim or implement it with a case. Mention the `models.luau` effect of the `isModel` change.

### F8 [low] check.sh points to an Implementation step that does not exist
Where: check.sh lines 37-38 ("run by Implementation step 13"); c0306.md Implementation steps (1 to 10; the slow tier is step 10)
Recommendation: Say step 10.

### F9 [low] AGENTS.md still says reviewers are pinned to Opus 5.5 (reported, as Design outcome 7 asks)
Where: `AGENTS.md:7` ("design and code reviewers, which the skills pin to Opus 5.5"); `.models.toml` `[roles.final-review]` is `claude-fable-5-2`; c0293's Non-goal keeps the text as it is
Evidence: After c0306, the skills name four review kinds. On main today the final review already runs on Fable. So every session reads a rule that two commands contradict.
Recommendation: Record it on c0293 (or capture a chore) so the line is reworded when c0293 lands. c0306 should not edit AGENTS.md, since c0293's prep holds it.

### F10 [low] The experiment records do not say the mutation loop and the probes ran under `./zn run`
Where: c0306.md E5 ("86 mutants ... run in throwaway worktrees reset between runs"), E6 (the `process.cwd` probe)
Recommendation: Record how they were bounded (the `./zn run --time` invocation, or that each was a spec-runner or gate run), as zz-review item 12 asks.

Lessons in harvest.md: the five new lessons and five notes are general rules another raft could fail, not restated findings. No finding.

Verdict: changes

# Review 004: c0247 (design mode)
Inputs: worktree `prep-ticket-confirms-intent` at 338d986d plus its staged `c0247.md`, `check.sh`, `acceptance/docs.spec.luau`, rounds 001 to 003 and their refutes, `harvest.md` and the three new lessons. A scratch clone under `$TMPDIR/rv247r4`: origin/main 5dd869b3, then the prep's staged diff, then `proto247.patch` (both applied cleanly). Also `./zn capture c0247` (53ad228c, no marker), and on origin/main: c0239, c0160, c0250, c0253 and c0256, `z-nile/engine/dispatch.luau` and `dispatcher.luau`.
Dropped from review-003: F1 (fixed: the dispatch sentence is first and exclusive, and its order against the plan-mode sentence is pinned; M25 re-run, killed), F2 (check.sh is fixed; the Design's leftover is in F5 below), F3 (fixed), F4 (fixed: the declined-plan-mode branch and the `Next:` line are pinned).

Round 3's fixes, re-run:
- **The prototype on today's main.** `./zn check c0247` in the clone: 7/7 in 4 min 4 s. AC7 selects 46 specs. AC6's merge base is 5dd869b3.
- **The dispatch branch.** Removing "never use plan mode and never only print: " (M25) fails AC2 with "does not say: Under `./zn dispatch` …". The dispatcher sets `ZN_DISPATCH = "1"` and `ZN_DISPATCH_DIR = stateDir` (`dispatcher.luau:898-900`). Its prompt tells every CLI "Nobody will answer a question … write `{stateDir}/questions.md` … and stop" (`dispatch.luau:156`). So `claude -p`, `grok -p` and `agent -p` all take the first sentence.

The final paragraph, read literally in each environment (on the prototype's text):

| environment | branch taken | outcome |
|---|---|---|
| interactive Claude Code, main session | "Otherwise, in Claude Code, when `EnterPlanMode` is offered" | right, provided the reader counts the tool as offered (F3) |
| a subagent | not offered (this reviewer's own loaded and deferred tool lists have no `EnterPlanMode` or `ExitPlanMode`), so "Without it … ; a subagent returns the restatement to its lead" | right |
| Claude Code already in plan mode | "skip it … write the restatement to the plan file … `ExitPlanMode`" | right for an empty plan; a plan the user is writing gets overwritten (F4) |
| the user declines plan mode | "or if the user declines plan mode, print the restatement and stop" | right |
| `claude -p`, `grok -p` or `agent -p` under `./zn dispatch` | the first sentence, exclusive | right; the retry's reply counts as the approval (c0256) |
| another CLI, interactive (Grok, Cursor) | "Without it", so print and stop | right ("confirm in their own way") |

Read with R0052's text on origin/main, nothing contradicts:
- Step 6's "Under the dispatcher, land without asking (the user started it)" comes after the confirmation. My mutant "create and land without asking" turns `c0117/docs` red, so AC7 guards that sentence.
- The Headless section's `questions.md` format (`## Q<n>`, options and costs) is the one the dispatch sentence names. The dispatcher prompt's "capture this as one issue" matches "follow it".

Scope: the title, the Problem and the three Solution bullets are as captured, plus the two `Decided with the user` lines. Every captured outcome has a Design and a Checked criterion. No narrowing.

### F1 [high] AC2 and AC4 pin each sentence and the order of only one pair, so moving, reordering or adding sentences keeps every pin while dropping plan mode in Claude Code or filing without approval
Where: `acceptance/docs.spec.luau` AC2 (the `at(dispatch) < at(otherwise)` assertion) and AC4 (the `**Confirm intent first.**` < step 0 assertion); Rules and mutants; lesson `z-design/most-specific-environment-first` ("AC pins the order of the two sentences")
Evidence: I ran each mutant on the clone with `scratchpad/mut/mutate.py` and `run.sh`, through `./zn run`, using `lune run tests/run -- .tracker/issues/c0247/acceptance/docs.spec.luau` from `z-nile/`. The control M25 failed AC2, as recorded. Each of these passed **5 passed, 0 failed**:
- **reorder**: the "Without it, or if the user declines plan mode, print the restatement and stop …" sentence moved to right after the dispatch sentence. The text now reads "Under `./zn dispatch` … and stop. Without it, … print the restatement and stop until the user answers; … Otherwise, in Claude Code, when `EnterPlanMode` is offered …". To a literal reader "it" is the dispatch, so an interactive Claude Code session prints and stops and never uses plan mode. That drops the captured "In Claude Code this is plan mode".
- **reorder2**: the dispatch sentence stays first, but the "Without it" sentence comes before the plan-mode sentence. Same effect, and "Otherwise" is now dead.
- **insert**: "Plan mode is only for tickets of type feature." added between the dispatch and plan-mode sentences.
- **move**: the plan-mode and "Without it" sentences moved out of the paragraph, to just before `## Lessons` (after step 6 and the Headless section). Step 0 still says "after the confirmation above", but the mechanism is now below it.
- **exempt**: "A one-line request is clear enough and is filed at once." appended inside the paragraph. That contradicts the Problem's "create the stub only once they approve". AC3 forbids only the literal "files from a skill rule".
Critique: round 3 found that the order of the environment branches decides the outcome. The fix pinned one pair. But the chain has three links ("Under dispatch" → "Otherwise, in Claude Code" → "Without it"), and the second and third refer back to what comes before them. The mechanism, sentence pins plus pairwise order, still leaves the meaning unpinned. The tempting fix is a second pair assertion (otherwise < without). That kills reorder and reorder2 but not insert, move or exempt.
Consequences:
- Putting the whole paragraph in the promoted spec would make every later addition to it an Override (lesson `zz-test/promoted-specs-pin-rules-not-sets`).
- An exact-text check must take its expected text from a sequestered file, not from `c0247.md` (lesson `zz-test/pin-expected-text-not-documents`).
- A whole-file diff of `SKILL.md` would go red when a raft mate edits z-ticket (lesson `zz-test/no-change-claims-check-behaviour-not-the-raft-diff`). So the exact check covers the paragraph line only.
Recommendation:
- **The promoted spec (a rule, kept after `done`):** in AC2, assert `at(dispatch) < at(otherwise) < at(without)`, and assert that all three lie between `at("**Confirm intent first.**")` and `at("0. **Open a capture worktree first**")`. This kills reorder, reorder2 and move.
- **check.sh (today's text, not rerun after `done`):** a new AC8 that the single line starting `**Confirm intent first.**` equals the Design's paragraph byte for byte. Hold the literal in `check.sh`, for example a quoted heredoc compared with `grep -F -x`, or a `cmp` of the extracted line. This kills insert and exempt, and any other addition inside the paragraph.
- Add rows M29 to M33 (reorder, reorder2, insert, move, exempt), run them, and record the results in E1.
- Change the lesson's How to apply to "pin the order of every branch and their place in the paragraph, and pin the paragraph's exact text in check.sh", not "the order of the two sentences".
Lesson: z-design/most-specific-environment-first

### F2 [medium] Nothing orders c0250 after c0247, but c0250 replaces the `questions.md` that AC2 pins, so a c0250 done first, or in the same raft, turns a correct c0247 red or makes it ship a superseded mechanism
Where: Design, Existing work ("c0250 … will have to override the pinned `questions.md` sentence of AC2 and change the paragraph in the same raft"); `check.sh` AC2; `depends_on: [c0256]`
Evidence:
- c0250 on origin/main has `depends_on: [c0117]`, is `new` and is planned as layer 3 of R-vision (c0248 to c0254). Its Solution says "Replaces `questions.md` in c0117's design". The README (line 82) says `escalation.md` "replaces c0117's local `questions.md`", and c0253's worker loop runs over the dispatcher.
- c0247 waits for c0256, which is still `new`/`draft` and outside R-vision. So c0250 can easily finish first.
- If it does, c0247's sequestered AC2 still requires "write the restatement as the question in `$ZN_DISPATCH_DIR/questions.md` and stop", and c0247's executor can't edit that.
- If z-raft groups the two, a correct c0250 can't change c0247's paragraph without turning c0247's AC2 red. The sentence in Existing work only works if c0247 is done first, and no `depends_on` says so (lesson `z-ticket/carry-the-plan-order-into-depends-on`).
- c0256 (dispatch retry passes the answer) may also be superseded by c0250's `./zn resolve <id> retry`.
Critique: the user decided "Restate via questions.md" (review 001 F1), and that isn't in question here. What's missing is the order that keeps the decision implementable. The tempting fix is to leave it to c0250's prep, which then finds a sequestered check it can't override.
Consequences:
- Adding `c0247` to c0250's `depends_on` puts R-vision's layer 3 behind c0256 and c0247. That changes the user's planned stack order, so it is the user's call.
- The other order needs a recorded rule: a c0250 that lands first sends c0247 back to design (`design: draft`, re-prepped so the dispatch sentence names `escalation.md`), and c0256 is re-judged.
Recommendation: escalate to the user: (a) add `c0247` to c0250's `depends_on` in this prep's PR (c0247 and c0256 land before R-vision's layer 3; nothing is re-prepped); or (b) keep R-vision's order, and write in c0247's Existing work and in c0250's Problem (a `Decided with the user` line) that if c0250 is done first, c0247 returns to design and c0256 is re-judged against `./zn resolve` (cost: one more c0247 prep round). Either way, replace "in the same raft" with the order chosen, and have z-raft never group the two.
Lesson: z-design/quote-other-preps-before-promising

### F3 [medium] Unknown: whether "when `EnterPlanMode` is offered" holds when the main session lists the tool only by name as a deferred tool, since a literal reader may then take "Without it" and print
Where: the pinned plan-mode sentence; E2; OC1
Evidence:
- This harness lists some tools only by name, as deferred tools whose schemas must be loaded with ToolSearch before a call. In this reviewer's session, `EnterWorktree`, `ExitWorktree`, `Monitor` and `TaskStop` are deferred.
- E2 records that `EnterPlanMode` "entered at once". It doesn't record whether the lead found it among its loaded tools or loaded it from the deferred list. I can't see the main session's tool list from a subagent.
- If it is deferred, "offered" is ambiguous. A reader that looks only at its callable tools prints and stops. That silently drops the captured outcome "In Claude Code this is plan mode", and no spec can see it.
Critique: this is an unproven assumption about the harness on the main path, with no pass/fail question in Unknowns. The tempting fix is to assume that "offered" covers deferred tools.
Consequences: if the tool is deferred, the sentence names how to reach it. That adds one pinned clause, and M-rows for the clause.
Recommendation:
- Add E5, run once by the lead in an interactive main session: is `EnterPlanMode` among the callable tools, or only named as deferred? Record the answer.
- If it is deferred, or the answer varies by version, write "when `EnterPlanMode` is offered (among your tools or as a deferred tool: load it with ToolSearch)", pin it in AC2, and add a mutant row that drops the parenthesis.
- Have OC1 check that plan mode opens without the user asking for it.

### F4 [low] Already in plan mode with a plan of the user's in the plan file, the paragraph overwrites it and `ExitPlanMode` approves a ticket in place of the user's plan
Where: the pinned clause "(skip it when you are already in plan mode), write the restatement to the plan file, ending with the line `Next: …`"
Evidence:
- A user planning something else in plan mode says "capture a ticket for X". A literal reader writes the restatement to the plan file, ending with `Next: capture with the z-ticket skill, steps 0 to 6; build nothing.`, and calls `ExitPlanMode`.
- The user's draft plan is lost, and their approval leaves the plan mode they were using.
Recommendation: when already in plan mode, print the restatement in the plan-mode conversation and wait. The user is in plan mode, so "In Claude Code this is plan mode" still holds. Or add the restatement to the plan file as its own section, keeping what is there, and don't call `ExitPlanMode`. Pin whichever is chosen in AC2 and give it a mutant row.

### F5 [low] Stale and mismatched text: the AC7 time, the AC2 labels, an impossible fallback for c0239 and a rule without a row
Where: Design, Affected specs; Test plan; Checked AC2 and `check.sh` AC2's label; Existing work; Rules and mutants
Evidence:
- **AC7's time.** Affected specs still says "(`git grep -lE 'SKILL\.md|README\.md'`, about 45 seconds)". The refute of review 003 F2 says it was fixed. My full check took 4 min 4 s.
- **AC2's labels.** The Test plan names the AC2 case "plan mode where it is offered, and the other readers print, return or ask through questions.md". The spec's case is "a dispatched run asks through questions.md first; elsewhere plan mode, printing or returning to the lead". The Checked AC2 statement and `check.sh`'s label still list dispatch last and don't say it is first and exclusive (lesson `z-design/spec-design-correspondence`).
- **c0239.** Existing work says "z-raft keeps the two apart or c0239's executor allows the folder". c0239's AC8 allow-list (`OVERRIDES='^z-nile/tests/acceptance/(c0239/|c0114/…)'`) is in its sequestered `check.sh`, which its executor can't edit. So only the first option exists.
- **A rule without a row.** "the stub is made from the approved version" (pinned in AC1) has no Rules-and-mutants row.
Recommendation:
- Say "a few minutes" in Affected specs.
- Make the Test plan's AC2 name match the spec. Reword the Checked AC2 and its `check.sh` label as "under dispatch, on any CLI, the question in `questions.md` first and exclusively; otherwise plan mode where `EnterPlanMode` is offered; otherwise print and stop; a subagent returns it to its lead".
- Replace the c0239 fallback with "z-raft must not group c0247 with c0239 unless c0239 is done first".
- Add a row for "made from the approved version", with a mutant that removes that clause.

Lessons pass (`./zn lessons --when design --full`):
- z-design/most-specific-environment-first: F1. The order pin covers one pair of a three-branch chain.
- z-ticket/carry-the-plan-order-into-depends-on and z-design/quote-other-preps-before-promising: F2.
- z-design/spec-design-correspondence: F5.
- zz-test/pin-expected-text-not-documents and zz-test/promoted-specs-pin-rules-not-sets: shape F1's recommendation.
- z-design/results-land-on-every-path, z-design/trace-every-way-code-runs and z-design/confirm-overrides-with-a-suite-run: satisfied (the table above; AC7's 46 specs pass on the prototype).

Harvest:
- `z-design/most-specific-environment-first` is a real lesson another raft could fail, but its How to apply ("pins the order of the two sentences") is the gap F1 shows.
- The zz-test lesson's `check:` now matches its note.

Candidate lesson (for the lead to file, z-design or zz-test): a sentence pin proves the words exist, not what they mean in place. Where meaning depends on order or on back-references ("Otherwise", "Without it"), pin the order of every branch and their place, and pin the exact paragraph in check.sh. Check: does a mutant that keeps every pinned sentence but reorders, moves or adds one still pass?

Verdict: changes

# Review 003: c0247 (design mode)
Inputs: worktree `prep-ticket-confirms-intent` at 338d986d plus its uncommitted `c0247.md`, `check.sh`, `acceptance/docs.spec.luau`, `design-refute-001.md`, `design-refute-002.md`, `harvest.md` and the two new lessons; `proto247.patch` applied with `git apply --3way` on today's origin/main ae2a123e (R0052, R0081 and R0085 merged; 217c1b13 since then adds only two tracker commits that touch none of these files), in a scratch clone (`scratchpad/rv5`); `./zn capture c0247` (53ad228c, no marker); c0256 on origin/main; `z-nile/engine/dispatch.luau`, `dispatcher.luau`, `adapters.luau` and `z-nile/lib/select.luau` on origin/main; the Claude Code 2.1.319 binary's strings, for the plan-mode tools.
Dropped from review-002: F2 (the declaration is gone and none is needed, see below), F3 (AC7 now finds the corpus scanners), F5 (fixed). F1 is fixed (below). F4: E2 answered its main question; the remaining dialog cases are F4 below, at low.

Round 2's fixes, re-run:
- **Prototype on today's main.** The patch applies cleanly to origin/main ae2a123e, next to R0052's step 6 sentence and Headless section and R0085's new README sections. `./zn check c0247`: 7/7.
- **The retry-reply sentence** is pinned (AC3, M8). c0256's Solution on origin/main now carries the four points the Design lists. c0256 has `depends_on: [c0117]`, c0117 is done, and z-ready refuses a member whose outside `depends_on` isn't done, so c0247 can't run before c0256.
- **No declaration, no c0165.** c0165 is done on main (3052ce61, R0081). `sel.forces` (`z-nile/lib/select.luau:100`) returns `z-nile` for any path under `z-nile/` outside `z-nile/tests/`, and `isInput` (line 207) treats a forced path as an input of every spec of that project, so result reuse can't skip the c0247 spec after an edit to these files. `lune run z-nile/affected -- z-nile/skills/z-ticket/SKILL.md z-nile/README.md` prints `ALL`. The dependency isn't needed.
- **AC6 against the merge base.** In rv5 the merge base is origin/main itself, which includes R0052's step 6 edit. AC6 passes because only text changed and the headings didn't. M16 was run in round 2.
- **AC7.** On today's main it selects 46 specs, not 40: c0117's four, c0165 `docs` and c0259 `readme` are new. On the prototype: 322 passed, 0 failed, in 144 s (F2). c0239's and c0160's Overrides touch none of these readers. My mutant that "reconciles" step 6 with the new rule ("land once the user has approved the restatement") makes `c0117/docs` fail ("z-ticket does not say: Under the dispatcher, land without asking"), so AC7 guards R0052's sentence too. I found no way for a correct implementation to turn AC7 red.
- **The plan-mode wording** matches E2: the restatement goes in the plan file, and a rejection means ask and restate.
- **R0052 and the new paragraph, read together** (rv5's `SKILL.md`): they agree on the interactive path. Step 6's "land without asking (the user started it)" is about landing, which comes after the confirmation. The Headless section's format (`$ZN_DISPATCH_DIR/questions.md`, `## Q<n>` with options and costs) fits "write it as the question in `questions.md`". They disagree in one place: F1.

Capture comparison: the title, the Problem and the three Solution bullets are as captured. The only additions are the two `Decided with the user` lines. Every captured outcome has a Design and a Checked criterion. No narrowing.

### F1 [high] Under `./zn dispatch` the paragraph gives two or three branches and doesn't say which one wins, so a headless run can print and stop, or enter plan mode, instead of writing `questions.md`
Where: pinned AC2 sentences "In Claude Code, when `EnterPlanMode` is offered, call it … call `ExitPlanMode`: the user's approval is the go-ahead …" and "Without it, print the restatement and stop until the user answers; a subagent returns …; under `./zn dispatch`, write it as the question in `questions.md` and stop."; Decisions and limits, first bullet
Evidence:
- **A dispatched run is also "in Claude Code", or "without it".** The dispatcher runs each model step as `claude -p <prompt> … --permission-mode bypassPermissions --permission-prompts none --settings '{"sandbox":{"enabled":false}}'` (`z-nile/engine/adapters.luau:331-349`), or as `grok -p` or `agent -p`. It disallows no tool.
- **Whether `claude -p` offers plan mode is unknown.** In 2.1.319, `EnterPlanMode` refuses only when it is called from a subagent ("Only the main session can enter plan mode", `validateInput` on `agentId`). Otherwise `isEnabled()` defers to a flag I couldn't read. So whether a dispatched `claude -p` is offered the tool is unknown. If it is, the first sentence applies word for word. Nobody has run what `ExitPlanMode` returns with no user and `--permission-prompts none`:
  - if it is allowed, the paragraph calls that "the user's approval" and the ticket is filed with no confirmation;
  - if it is denied, the paragraph calls that "a rejection", and the run "asks what to change" of nobody.
- **I couldn't run the probe.** A nested `claude -p` was refused by this session's harness ("Create Unsafe Agents"), so only the lead can run it.
- **Grok and Cursor have no `EnterPlanMode`.** For them, "Without it, print the restatement and stop until the user answers" fits exactly as well as the later "under `./zn dispatch`" clause. A run that only prints leaves no `questions.md`, and the dispatcher then records `z-ticket made 0 issues on origin/main, not one` (`dispatcher.luau:1098-1106`). The user's answer is never asked for, which is the outcome the user's decision (review 001 F1, "Restate via questions.md") exists to prevent.
- **The Headless section doesn't settle it.** It says to write questions for "a scope change, a final review round …, a missing credential". It never says plan mode is off under the dispatcher, and the paragraph comes first.
Critique: the user's decision is carried out only if the dispatch clause wins, and the text lists it last, after two branches that also match a headless run. The tempting fix is to probe `claude -p` and, if plan mode isn't offered there, leave the text alone. That still leaves Grok and Cursor reading "Without it, print and stop".
Consequences:
- An exclusive dispatch branch changes the AC2 pins and the rows M4, M12 and M18.
- The subagent clause is unaffected: under the dispatcher z-ticket is the main session.
- The Headless section stays as it is. The new sentence names its format, so the two can't drift.
- No new state.
Recommendation:
- Open the mechanism sentence with the dispatch branch and make it exclusive, for example: "Under `./zn dispatch` (`ZN_DISPATCH=1`), on any CLI, never use plan mode or print: write the restatement as the question in `$ZN_DISPATCH_DIR/questions.md` (the Headless section's format) and stop. Otherwise, in Claude Code, when `EnterPlanMode` is offered, … ; without it, print the restatement and stop until the user answers; a subagent returns the restatement to its lead, which confirms it with the user."
- Pin it in AC2 as whole sentences, plus an order assertion: the dispatch clause's index comes before `EnterPlanMode`.
- Add mutant rows and run them on the prototype: (a) the dispatch clause back at the end; (b) "on any CLI, never use plan mode or print" removed.
- Record what `EnterPlanMode` and `ExitPlanMode` do under `claude -p --permission-mode bypassPermissions --permission-prompts none` as an experiment (E4) the lead runs once through `./zn run`. The rule above no longer depends on its answer, so E4 is a record, not a gate.
Lesson: z-design/trace-every-way-code-runs

### F2 [low] AC7 now takes 144 s, not about 45, and the numbers in the sequestered `check.sh` and the Design are out of date
Where: `check.sh` AC7 comment ("About 45 seconds"); Design, Overrides bullet and Affected specs ("the 40 promoted z-nile specs", "about 45 seconds")
Evidence: in rv5 on origin/main ae2a123e, the AC7 selection is 46 specs (`git grep -lE 'SKILL\.md|README\.md' -- tests/acceptance | grep '\.spec\.luau$' | grep -v '/c0247/'`). The run took 144 s: "slowest: tests/acceptance/c0117/dispatch-cli.spec.luau 143.4s, …/c0115/freeze.spec.luau 26.2s". `dispatch-cli` matches only through line 237's literal `` `z-nile/skills/z-design/SKILL.md` ``, so it never reads either edited file. Narrowing the pattern doesn't fix this. I tried `'z-ticket|README\.md|\}/SKILL\.md|(^|[^/])SKILL\.md'`: 23 specs, and it drops `c0115/absence`, the corpus scanner review 002 F3 was about, which also matches only through literal paths to other skills.
Critique: the check is right. Only the claims about it are wrong, and the comment is in a sequestered file that can't be fixed after this prep. The list grows with main, so a fixed count will go stale again.
Consequences: none beyond the text.
Recommendation: keep AC7's selection as it is. Drop the fixed count and time from the `check.sh` comment, or say "about 45 specs, a few minutes on 2026-11-06, growing with main". Make the same change in the Design.

### F3 [low] Text that went stale when R0052 and c0165 merged, a successor that will touch the pinned `questions.md` sentence, and a lesson that contradicts its own note
Where: Design, Existing work and Regression guard; Unknowns, Lessons pass; `zz-test/no-change-claims-check-behaviour-not-the-raft-diff`
Evidence:
- "**c0117 / R0052** (active, in code review)" and "In flight and untouched by this change: c0117 (its Headless section and step 6 sentence)" are out of date. R0052 merged (e8c832ff), and `c0117/docs.spec.luau` is now one of AC7's promoted readers. It pins step 6's "Under the dispatcher, land without asking (the user started it)" (my mutant above).
- The Lessons pass treats c0165's selector as unlanded. c0165 is done (3052ce61).
- R0085's README, now on main, says c0250 (captured) will bring "`escalation.md` … replaces c0117's local `questions.md`". When c0250 is built, the promoted c0247 spec's pinned "write it as the question in `questions.md`" needs an Override from c0250. Existing work doesn't name c0250.
- The new zz-test lesson's `check:` and How to apply still say "computed by `git grep -lF`". Its own appended note says the narrow path grep misses the corpus scanners and to use `-lE 'SKILL\.md|README\.md'`.
Recommendation:
- Update the two c0117 sentences: landed, and guarded by AC7 through `c0117/docs`.
- Say c0165 is done.
- Add c0250 to Existing work: its prep owns the Override of `tests/acceptance/c0247/docs.spec.luau` (lesson z-design/restated-rules-move-together).
- Make the lesson's `check:` and How to apply say "the specs that read what they read" (`git grep -lE` over the home's acceptance specs, so a corpus scanner is included), not `-lF`.

### F4 [low] (follows review-002 F4) Two plan-mode dialog outcomes still have no branch
Where: pinned AC2 sentence; E2; OC1
Evidence: from the 2.1.319 binary's strings:
- **`EnterPlanMode` can ask first.** Under a condition I couldn't resolve, its `checkPermissions` returns `{behavior:"ask", message:"Enter plan mode?", personOnly:true}`. E2 didn't see this prompt in the user's setup, but a user who declines it lands in no branch. "Without it" means the tool isn't offered, not that the user said no.
- **Context clearing is off by default.** The approve dialog's "clear context" choice is behind `showClearContextOnPlanAccept` ("When true, the plan-approval dialog offers a 'clear context' option. Defaults to false."), and neither `~/.claude/settings*.json` nor the project's settings set it. So review 002's context-clearing concern holds only for a user who turns that option on. Such a user's fresh context holds only the restatement, which reads like an implementation plan.
- **"Yes, and auto-accept edits"** changes the session's permission mode. That's the user's own choice, so nothing needs fixing.
Recommendation:
- Add "if the user declines plan mode, print the restatement and stop", pinned in AC2, with a mutant row.
- End the restatement with one line naming the next step, e.g. "Next: capture this with the z-ticket skill, steps 0 to 6; build nothing". This costs one pinned clause and keeps a cleared context from implementing the plan.
- OC1 checks both.

Lessons pass (`./zn lessons --when design`):
- z-design/trace-every-way-code-runs (F1: the dispatched CLIs are a way the text runs that the branch order doesn't handle).
- z-design/results-land-on-every-path (round 2's F1 is now satisfied).
- z-design/restated-rules-move-together and z-design/quote-other-preps-before-promising (F3: c0250).
- z-design/run-the-other-rafts-specs: satisfied; c0117's promoted specs pass on the prototype.
- z-design/confirm-overrides-with-a-suite-run: satisfied; AC7's run is 322/0.
- z-design/declare-what-full-runs-covered: satisfied by the forcing rule, confirmed in `select.luau`.
Harvest: `z-design/declaration-checks-use-the-exact-key` is a real lesson another raft could fail. The zz-test lesson is real too, but its `check:` contradicts its note (F3).

Candidate lesson (for the lead to file): z-design: a rule that branches on where the agent runs (interactive CLI, CLI without the tool, subagent, dispatcher) puts the most specific environment first and makes it exclusive, because a headless dispatched run also matches "in Claude Code" or "without it" (c0247 design review 003 F1). Check: for each environment the dispatcher can run this skill in (`claude -p`, `grok -p`, `agent -p`), which branch does a literal reader take first?

Verdict: changes

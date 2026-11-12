# Review 010: c0261 (design mode)
Inputs: prep worktree `.worktree/prep-c0261-redesign` at 7f85414e plus its uncommitted redesign (c0261.md, check.sh, the 16 files of acceptance/; the redesign is judged, design-review-001..009 were read only for what they already answered); prototype `proto-c0261` at aca38100 (pushed; `cmp` of its check.sh and acceptance/ against the prep's: identical); its diff against main 10dd3c85; capture `./zn capture c0261` (6d79d26f, no marker) and the Problem as elaborated by the user's capture PR 081392e0; `./zn find` c0260, c0262, c0264 (c0264's check.sh, experiments/merges.sh, mutants.sh); the skills zz-review, zz-rules, zz-arch, zz-test, z-design, zz-execute; `./zn lessons call site`.
Runs (all bounded): on the prototype, the 103 promoted specs of AC12's grep (741 pass, 7 fail: exactly the five Overrides cases and the two c0116/compact-record cases already red on main, so the Overrides line holds) and the 132 specs `lune run z-nile/affected` selects for the Touched modules that AC12's grep does not (904 pass, 6 fail); the 4 files holding those 6 failures on main's engine (the prep worktree): the same 5 cases fail there (plus the nested one), so none is this issue's. Probes through `./zn run`: `grok models`, `agent --list-models`, and a scratch git repo for the cutoff query.
Model: claude-opus-5-5

### F1 [high] The default makes every layer's code review run on the author's own model, removes a standing user rule without a user line, leaves the Code-mode checklist with no expensive reviewer, and Open question 12 misstates what a veto costs
Where: c0261.md:69 (`zz-review-code` row), :78 (the **(prep)** sentence), :116 (Open question 12); acceptance/docs.spec.luau:95-108 and :160; acceptance/models-activities.spec.luau:223-241; acceptance/root-file.spec.luau:38-58; z-nile/skills/zz-review/SKILL.md:104-110 (Final mode); the prototype's zz-execute Phase 4 step 2.
Evidence: main's zz-execute Phase 4 step 2 says "Run the reviewer on the **review model of the CLI** (the user's rule) … whatever model the author runs on: a reviewer on the author's model shares its blind spots" (a rule since c0380, "reviewers run on the strongest model", #5). The redesign's `zz-review-code` cells are "same as `z-ticket`", which is also z-run's: `claude-sonnet-5-5` high, `grok-4.6` high, `cursor-grok-4.6-high`. So on every CLI the layer reviewer is exactly the author's model, and docs.spec.luau:108 pins the removal of the blind-spots sentence. The approved first design kept an Opus Code-mode round at the end of every code review. In the redesign, the only expensive review after the layers is Final mode, and that mode only fills and checks the trace and judges claims (zz-review SKILL.md:106-110). It has none of Code mode's items: sequestration (2), weak tests (3), architecture (5), performance (6), repository safety (8, the "Caught only by review" list that AGENTS.md says "review must catch") and bounded commands (11). So under the default, no expensive model ever applies the Code-mode checklist. The design's claim that the stack's final review "now carries the safety" (:78) is not what Final mode checks. Q12 calls the veto "a one-line change in the root file". In fact, deleting the `zz-review-code` tables turns sequestered cases red:
- models-activities "every final-review activity is named …" (`FINAL_REVIEWS["zz-review-code"]` must be false);
- root-file "every final review … ranks above the rounds on the way" (`zz-review-code` stays in WAY and then resolves to rank 4, which is not above 4);
- root-file's EXACT case (`IDS.way`);
- docs.spec :95-108 and :160 (`model: "sonnet"` for a layer's code review, "A layer's code review is the work on the way", AGENTS.md's "a layer's code review and the work on the way run cheap").

A veto is therefore a new contract and a new `./zn approve`. The README's c0251 line as the prototype rewords it ("author Sonnet, a reviewer of another family such as Opus …") states the opposite of the default.
Critique: reading "the final code review round" as the stack's final review is defensible, and the Problem says "middle review rounds … run cheap". So this is not by itself a cut of a captured outcome. But the default does two things the user has not seen: it drops a rule the skills label as the user's, and it leaves the Code-mode checklist with no expensive reviewer. "Keep your guesses" (2026-11-07) covered model cells in a design where every code review ended on Opus. The tempting fix is to reword Q12 and keep the default. That still leaves the default pinned in the contract the user is asked to approve.
Consequences: making layer reviews expensive costs about one Opus review per ticket. Keeping them cheap but on another model needs a claude cell other than Sonnet: Opus is expensive and Haiku is weaker. Keeping them cheap and widening Final mode makes the final review larger (a longer prompt, and the Code-mode items applied to the whole stack diff), and it changes #297's Final mode text, which docs.spec must then pin.
Recommendation: escalate to the user: before `./zn approve c0261` (the human step the redesign needs anyway), ask Q12 with its real consequences and record the answer as a `Decided with the user` line. Options:
- (a) Keep the default as it is, accepting that the layer reviewer is the author's model and that no expensive model applies Code mode.
- (b) Run layer reviews expensive: `zz-review-code` joins `FINAL_REVIEWS`, its tables go, and the blind-spots sentence stays. The cost is one Opus review per ticket.
- (c) Keep layer reviews cheap, and Final mode also applies Code mode's items 2, 3, 8 and 11 to `git diff origin/main...HEAD`, so one expensive review per raft covers sequestration and repository safety. Add a docs.spec case that pins those items in Final mode.

Whichever the user picks, rewrite Q12 to list the cases a veto changes (above) instead of "one line", and make the README's c0251 parenthesis agree with the answer.

### F2 [high] AC11's "a typed `--model` wins over the measured one in `./zn spend`" passes a never-wired implementation: only the pure function is tested
Where: acceptance/spend-model.spec.luau; c0261.md:228 (Rules row "measured first | run"); prototype z-nile/engine/main.luau:6521.
Evidence: `chooseModel` is called only inside `if since then`, that is, only when the checkout's buffer holds a `--begin` line for the phase. No `./zn spend` in final-round-cli, final-round-raft or final-round-newraft writes a begin line, and none has a transcript in the span, so `modelId` is the typed value whether or not the call site uses `chooseModel`. A `cmd.spend` that keeps main's `if got.model then modelId = got.model end` passes every AC11 spec. The Rules row's mutant was applied to `spend.chooseModel` itself, not to the place where the measured value replaces the typed one.
Critique: this is the case the redesign added #294 for. The interactive review row that the refusal checks is the one a measured author model would overwrite. Without a case, the executor can leave main's precedence in place and check.sh stays green.
Consequences: the case needs a fixture HOME (sessionread reads `process.env.HOME`) with a Claude jsonl under `.claude/projects/<the fixture cwd, slashes as dashes>`, in the span and naming a Sonnet model (tests/tooling/measure.spec.luau has the line format). The case must not read the real `~/.claude`.
Recommendation: add a command case to final-round-cli:
1. `./zn spend <id> --phase design-review --begin`, then a fake transcript in the span on `claude-sonnet-5-5`.
2. `./zn spend <id> --phase design-review --model claude-opus-5-5 --note design-review-001`: the row's model is `claude-opus-5-5`, and `status <id> prepared` passes.
3. The same span without `--model`: the row records the measured Sonnet, and the move is refused.

Add the Rules row "the call site lets the measured model win | final-round-cli :: …".
Lesson: zz-test/kill-mutants-where-the-value-is-built

### F3 [medium] The refusal's evidence is a typed claim, even for a dispatched final review: the dispatcher's own measured row never matches the round's subject
Where: c0261.md:90, :98, :101; prototype finalround.luau `isRoundRow`; prototype dispatcher.luau `record` (the code-review path that appends to the author's buffer) and main.luau `recordAndCommit`.
Evidence: for the final kind, a row matches only with the subject `<R-id>: final-review-NNN`. The dispatcher appends its measured row (the runner's tokens and the model it started) to the author's buffer with `subject = note`, that is, `final-review-001`, which never matches. The one row that matches is the author's `./zn commit -m "<R-id>: final-review-001" --model <id>`, and `recordAndCommit` writes it with the typed model and `tokens = nil`. So even a dispatched final review passes or fails on what the cheap author copies, and an interactive review passes on what the lead types. Claude Code's Agent tool runs a subagent on the parent's model when `model:` is left out, and a lead typing `--model claude-opus-5-5` by rote then passes both refusals. Meanwhile sessionread already walks every jsonl of the project in the span, subagent transcripts included, and keeps only the first model it finds (`add`). Reversing #294's measured-over-typed precedence (F2) discards that evidence and records no user line.
Critique: "Commands refuse" was the user's answer. As built, it guards against a forgotten `--model`, not against a review that ran on the wrong model. The design says so only for interactive rows ("its model is the lead's report"), and states the dispatched path as "the dispatcher writes the row with the model it started", which is not true for the final review.
Consequences: an agent CLI transcript has no model, so the check can't be made there and the typed value stays. A span in which the lead's own session ran Opus would mask a Sonnet reviewer, so the check only catches the case where no model of the kind ran.
Recommendation:
- Give the dispatcher's buffered row of a final review the subject it prints (`<R-id>: final-review-NNN`). A dispatched final review then proves itself, and the author's copy does not decide it.
- Have sessionread return the set of models in the span. When the span was read (claude or grok) and none of its models is of the typed model's final-review kind, `./zn spend` and `./zn commit` record the measured model, or refuse and name both.
- Cases: a dispatched final review where the author types a Sonnet id still passes, on the measured row; an interactive span with only Sonnet and a typed Opus is refused.
- If the user prefers a check on the honour system, record that as a `Decided with the user` line and say in zz-rules that the refusal guards against forgetting.

### F4 [medium] The dispatched raft review's row loses the runner's tokens and time, so the cost per model under-counts every raft review
Where: c0261.md:103; prototype dispatcher.luau:531-555; acceptance/final-round-dispatch-raft.spec.luau (no assertion on tokens).
Evidence: the raft-mode path runs `./zn spend <R-id> --phase design-review --model <a.model> --note <note>`. Since #294, `./zn spend` takes no tokens. It measures the span since a `--begin` line of that phase in the author's buffer, or else writes the row `unmeasured`. So the dispatcher prints `spend: <R-id> design-review <a.tokens> tokens`, but the row holds either no tokens or the author's whole span summed under Opus. The code-review branch of the same `record` function already appends the runner's measured row (tokens, wall, cpu, model) to the author's buffer. Also, :103 says "published once", but `./zn spend` pushes nothing since #294 (the spec's own header says so).
Critique: one of the captured outcomes is that the cost per model shows, and the raft review is one of the expensive reviews this issue makes visible.
Consequences: if the buffered row already carries `<R-id>: design-review-NNN`, the fold must not prefix it a second time (cmd.spend prefixes the note). Only the primary member gets the tokens, as cmd.spend already does for a share.
Recommendation: append the runner's measured row to the author's buffer with the subject `<R-id>: design-review-NNN` and its tokens, wall, cpu and model, and let `./zn spend <R-id> --phase design-review` fold it into the members. Extend final-round-dispatch-raft to check:
- the row's tokens equal the fake CLI's count;
- the subject is not prefixed twice;
- there is still exactly one row and nothing pending.

Fix the "published once" text.

### F5 [medium] The by-model table's minutes column sums the legacy typed minutes, which every row since #294 records as 0
Where: c0261.md:90 ("re-checked against #294"); prototype ledger.luau:277; acceptance/metrics-model.spec.luau (its spend.d row has `minutes 0`, and the pinned `2.0` comes from the spend.md rows).
Evidence: `cmd.spend` and `recordAndCommit` write `minutes = 0, how = "measured"` and keep time in `ai` and `wall`. #294's own note: "metrics keeps the old typed minutes in their own column". `ledger.byModel` adds `r.minutes`, so for all new work the time per model reads 0.0.
Critique: the cost per model is the captured outcome, and half of what the table shows is dead for every new row. The spec pins that behaviour.
Consequences: AC6's pinned header and rows change, so this is a sequestered spec edit now. Rows marked `unmeasured` need their own treatment, either counted apart or shown as unknown.
Recommendation: sum the measured AI time (`ai` seconds as minutes, falling back to `wall`) in a column of its own, beside the legacy minutes, for example `| model | tokens | ai minutes | typed minutes | rows |`. Add a case where a spend.d row with `ai = 120, minutes = 0` shows 2.0 in the measured column, and decide in the case how unmeasured rows show.

### F6 [medium] The landing minute is the layer commit's time, not the landing's, so an item whose first review falls between the two is locked out
Where: c0261.md:100; prototype main.luau `finalRoundRefusal` (`git log --diff-filter=A --format=%ct --reverse origin/main -- z-nile/engine/finalround.luau`).
Evidence: `./zn done` lands a stack with a `--no-ff` merge (#296), so the layer commit that adds finalround.luau keeps its own date. A scratch repo run through `./zn run`: the layer was committed at 2026-11-05 and merged with `--no-ff` at 2026-11-09. The prototype's query prints `2026-11-05 … layer`; with `--first-parent` it prints `2026-11-09 … done`. An issue prepped by another session in that window records its first review row under main's old skills (no `--model`). After c0261 lands, that issue is bound and refused. That contradicts the design's "An item in flight at the landing is never locked out". The final-round-cli cutoff cases use 2020 and 2099 and the seed commit, so they can't see the window.
Critique: the window runs from the layer's finish (or last restack) to `done`, so it spans at least the final review.
Consequences: on a branch (the case fixtures) `--first-parent` still finds the commit that added the file, so nothing else changes.
Recommendation: use `git log --first-parent --diff-filter=A …`. Add a final-round-cli case: finalround.luau added on a side branch at T0, merged `--no-ff` into origin/main at T1, a row dated between T0 and T1 is not bound and one dated after T1 is. Add a Rules row "the landing is the merge on main | … | the layer commit's date".

### F7 [medium] Three wiring paths of AC5 and AC10 have plausible mutants that no case kills, and the grok model list never parses
Where: c0261.md:80, :83; acceptance/dispatch-activities.spec.luau (the gate cases); acceptance/dispatch-wait-cli.spec.luau; acceptance/dispatch-list-cli.spec.luau; prototype dispatcher.luau:921 (`parseModelList`), :989 (z-wait's cwd per gate), :2105 (`--until`).
Evidence:
- (a) Every gate case is an issue at the prep gate, and dispatch-wait-cli drives only prep PRs. A `gate()` that waits only when `name == "prep"` passes them all: the rafting PR stops at exit 4, and the user's "all the way to merge" is unmet there. The `--gate raft` worktree has no case either.
- (b) The chain passes `action.waitFor or "checks"`. A chain that always passes `checks` passes every case. A green PR whose merge state is UNKNOWN (the common case right after another prep merged) then polls `gh pr checks`, which ends 0 at once. `waitedHead` is set, UNKNOWN is read again, and the chain stops with exit 4.
- (c) The real `grok models` output (probed today): `Available models:` / `  - grok-4.7` / `  * grok-4.7-build-fast (default)` / `  - grok-4.6` / `  - grok-4.5`. Neither of `parseModelList`'s patterns matches a bulleted line, so the list is `{}`. Every grok try prints "the grok CLI's model list could not be read (empty)" and fails open. E1 recorded the ids, not the format. `agent --list-models` ("id - Name") does parse.

Critique: these are the wiring paths of the user's "all the way to merge" and of the ordered preference. The first design's escalated paths were closed for the prep gate and for agent only.
Consequences: a grok list that parses makes `available` compare `spec.model` (`grok-4.7`, without the effort), which matches the bullets. A list read only for CLIs with a `fallback` would drop grok's read altogether.
Recommendation: add these cases:
- a raft-gate wait: in `next`, and in dispatch-wait-cli with a rafting PR, where the step's cwd is the raft worktree;
- a dispatch-wait-cli case with a green PR that is UNKNOWN, then MERGEABLE: the log shows `gh pr view <n> --json mergeable`, then the merge;
- `parseModelList` cases on the verbatim outputs of both CLIs, recorded in E1. Alternatively read a list only for a CLI whose spec has a `fallback`, and say so in the design.

Add one Rules row for each.

### F8 [medium] The final-review list is an allow-list: the full-force review the Problem names (c0262) is unbound, its reserved name now belongs to #297's review, and the notes to c0260 and c0262 contradict this design's own promoted spec
Where: c0261.md:71, :78, :120; acceptance/models-activities.spec.luau:223-241; acceptance/dispatch-activities.spec.luau:31-40; c0262.md Problem; c0260.md:70.
Evidence: c0262's review runs "once per ticket, before its layer merges … on the sharp model (c0261)", which is not the stack's final review. Yet :120 tells c0262 that the stack's final review "is a final review here (`zz-review-final`)", the name the first design had reserved for c0262. Whatever mode c0262 adds (for example `zz-review-force`) falls back to `zz-review` only while no table names it. `reviewRule` doesn't bind it, so a `[zz-review-force.claude]` on Sonnet resolves without error. :78 says a mode with no `activity` field "needs none". :120 and the promoted dispatch-activities.spec say every entry names one, so a c0260 or c0262 redesign that follows :78 turns that promoted spec red. c0260's prepared design names its activity `z-ticket-review` (with three tables of its own and `reviewRule` covering it), not the `zz-review-idea` this design lists. The lesson's check: "Does every rule this design says another issue will follow appear in that issue's current documents".
Critique: "Sharp runs every final review: … the full-force review (c0262)" is a captured outcome. An allow-list leaves it to c0262 to remember. An on-the-way list makes it hold by default, which is the property :76 already claims ("a new review mode is expensive until someone gives it its own table").
Consequences: binding by name needs c0260 to use a `zz-review-…` activity. If it keeps `z-ticket-review`, the rule must also bind every activity a `REVIEW_MODES` entry names, and that needs the mode table where `reviewRule` runs.
Recommendation: replace `FINAL_REVIEWS` with `models.ON_THE_WAY = { "zz-review-code", "zz-review-stream" }` and bind every other `zz-review-…` activity. Cases:
- `[zz-review-force.claude]` on Sonnet is refused;
- `zz-review-code` on Sonnet is accepted.

Also:
- Delete the "needs none" sentence.
- Rewrite the c0262 note: its per-ticket review is final and bound by default, and any refusal of its own is c0262's.
- Quote c0260's current `z-ticket-review` and state what c0260's redesign must change (rename it to `zz-review-idea`), sent to that prep in this round.

### F9 [low] Regression guard: five cases in the affected set are already red on main and not listed
Where: c0261.md:159, :183-189.
Evidence: the 132 watch-selected specs outside AC12's grep, run on the prototype, gave 904 pass and 6 fail:
- c0049/parallel-runner "a single spec runs in-process …";
- c0045/workstreams "worktree --from bases the new worktree on the ref" and "stream review files are not review rounds";
- c0116/claims "a redesign landed after the carried move is caught by ready …";
- c0116/retired, through the nested c0114/classified "no feature or defect is filed in z-nile's root" (d0295).

All of them fail identically on main's engine (the prep worktree), so none is this issue's. The design still says the affected gate fails "only the cases named there". The counts are also inconsistent: "225 specs" against a gate run of "184 spec files".
Recommendation: name these cases under "Already red on main" so that the executor's affected gate is read correctly, and give one count. Consequences: none.

### F10 [low] Stale or incomplete texts an executor will trip on
Where and evidence:
- (a) Solution :56, the (prep) bullet, still says "`zz-review --final` selects the final round" and lists a `zz-review-design` table. Both are gone in the Design, and `--final` is pinned absent by docs.spec.
- (b) :175 says "see the Verification of this prep below", but the log is empty, and the prototype's tip (aca38100, branch `proto-c0261`) is named nowhere in the document ("tip in the report").
- (c) The prototype's `Action.waitFor` comment says "checks" or "merged". The design's values are checks, mergeable and merged.
- (d) Touched modules omits the three promoted spec files that step 9 rewrites (c0117/dispatch, c0117/models, c0008/done-order).
- (e) The Rules row for `done` says "three cases". final-round-done has one case, plus setup and cleanup.
- (f) The stated refusal for an unreadable origin/main or base history has no Rules row and no case.
- (g) c0264's experiments/merges.sh models c0261's rewording of the c0251 line as "(the author and the reviewer on different model families)". The redesign keeps model names and "successive rounds rotate". c0264's E3c rule ("keep c0261's wording") still resolves it, and its AC6 does not scan that subsection, but c0264 should be told the real wording.
- (h) The `.models.toml` header says "the review rounds on the way".

Recommendation: fix each in the one revision. Consequences: none.

Verdict: changes

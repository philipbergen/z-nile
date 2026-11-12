# Review 001: c0261 (design mode)
Inputs: prep worktree `prep-model-tiers-cheap-sharp-wait` at 4698e669 plus its uncommitted c0261.md, check.sh and acceptance/ (identical to the prototype's: `diff -r` clean); prototype `proto-c0261` (HEAD 2040bef9, an ancestor of origin/main 7efa4b7e) and its `git diff`; capture `./zn capture c0261` (6d79d26f) and the newest capture `git show origin/capture-workers:z-nile/.tracker/issues/c0261/c0261.md` (2e282833); sibling preps `prep-capture-interview-and-idea-review` (c0260) and `prep-full-force-final-review` (c0262); z-design, z-raft, zz-execute, zz-review, zz-rules skills; `./zn lessons --skill zz-review --full`, `./zn lessons --when design --full`.
Runs: the five c0261 specs on the prototype: 29 passed, 0 failed. `tests/acceptance/c0084/*.spec.luau`: on the prototype 34 passed, 2 failed; on the prep worktree (today's code) 16 of 16 for the two files that fail. AC13's own selection on the prototype: 125 passed, 1 failed (the c0117 docs case named in Overrides), which confirms the design's figure for that selection.

### F1 [high] Two promoted c0084 specs turn red on the prototype and aren't named in Overrides
Where: Regression guard (Overrides), Affected specs, check.sh AC13; Design, "Spend records the tier" ("New phase `wait` in `ledger.PHASES`").
Evidence: on the prototype, `../zn run --time 400 -- lune run tests/run -- $(ls tests/acceptance/c0084/*.spec.luau)` (from `z-nile/`) prints
`FAIL tests/acceptance/c0084/ledger.spec.luau :: lists the six phases in lifecycle order` (line 42: `toEqual({ "capture", "prep", "design-review", "build", "code-review", "deliver" })`) and
`FAIL tests/acceptance/c0084/metrics-phases.spec.luau :: sums agent-minutes by phase and type, in lifecycle order, with tokens` (line 146). Both pass on today's code (16 passed, 0 failed in the prep worktree). Neither is in Overrides. The author's Override search (`grep -rlF -e models.toml -e engine/models -e engine/dispatch -e engine/ledger`) and AC13's regex (`engine/(dispatch|dispatcher|models|ledger)`) both miss these specs, because they require the module through the other alias: `git grep -lE '@scripts/tracker/(ledger|models|dispatch|dispatcher)' -- tests` in `z-nile/` lists `tests/acceptance/c0084/commit-phase.spec.luau`, `c0084/ledger.spec.luau`, `c0084/spend-command.spec.luau` and `c0114/layout.spec.luau`. The claim that 125 of 126 cases pass (only the c0117 docs case fails) covers only the narrower selection.
Critique: the gate (`affected` prints `ALL`) goes red at execution on an override the design never declared. The obvious fix is to add the two cases to Overrides. That keeps a phase that the recording paths refuse anyway (see F4: `SPEND_PHASES` and `commit --phase`).
Consequences: keeping a `wait` phase means overriding two c0084 specs, adding `wait` to `SPEND_PHASES` (main.luau:4898) and to `commit --phase` (main.luau:3913), and adding a new `metrics` row that zz-stats must explain. The tier column already says "wait", so the phase adds nothing that the cost per tier needs.
Recommendation: drop the new phase. The z-wait row records the phase of the activity it waits on (`deliver` for an active raft's PR, `prep` for a prep PR), and its `tier = wait` cell carries the cost. Then no c0084 spec changes. If the design keeps `wait`, name both cases in Overrides with c0261 as the chore. Either way, widen the Override search and AC13's regex to both alias spellings (`(engine|scripts/tracker)/(dispatch|dispatcher|models|ledger)`) and paste the search's output in Affected specs.
Lesson: zz-review/lists-paste-their-search

### F2 [high] z-wait's poll doesn't wait: `merged` returns at once, `checks` stops at the first limit, and red CI reads as "not yet"
Where: Design, "Waiting"; `dispatch.waitCommand` / `waitPrompt` (prototype dispatch.luau); AC7 and dispatch-tiers.spec.
Evidence (run in the prep worktree):
- `./zn run --time 600 -- bash -c '[ "$(echo OPEN)" = MERGED ] || exit 3'` exits 3 in 0.25 s. `--time` is a limit, not a duration. So `--until merged` makes its "at most ceil(M*60/600) = 6" polls in about a second, and the step exits 4 ("the wait ran out") instead of waiting 60 minutes.
- `./zn run --time 2 -- bash -c 'sleep 30 || exit 3'` prints `bounded: stopped at the wall-clock limit` and exits **124**, not 3. A `gh pr checks <n> --watch` that hits the 600 s limit therefore ends with 124. The prompt says "If it ends with exit code 3, run it again … Stop when it exits 0", so the model stops after the first 10 minutes whatever `--minutes` says.
- `gh pr checks` returns non-zero for failed checks and when no checks have been reported yet (`gh pr checks --help`: "8: Checks pending", other failures generic). `|| exit 3` folds all of these into "not yet": a red CI is polled until the times run out and then reported as exit 4 "ran out", the same as a slow CI.
- On claude, the wait step's CLI is Claude Code. Its Bash default is 120 s (adapters.luau:309-315 raises only the maximum, BASH_MAX_TIMEOUT_MS). The wait prompt never tells the model to pass a timeout, so each 600 s poll is killed at 120 s. grok's and agent's shell limits are not measured at all.
- AC7's spec checks only substrings (`./zn run --time 600 --`, `gh pr checks 42`, `gh pr view 42`, `exit 3`). The mutant `gh pr checks 42 || exit 3` (no `--watch`) passes, and so does the instant `merged` poll.
Critique: the wait tier exists to replace a model that loops. As designed, it either exits at once or after one bound, and it can't tell "failed" from "not yet". The tempting fix is to add `--watch` or a `sleep` to `merged`. That still leaves exit 124 and the 120 s Bash default.
Consequences: a poll that loops inside its bound needs its own deadline below `--time`, so it ends with 3 rather than 124. It also needs a third outcome (failed or closed: stop now), a tool timeout the prompt states for each CLI, and a wall-clock budget kept by the dispatcher rather than a count of model calls.
Recommendation: make `waitCommand(until, pr, seconds)` a loop that is its own clock:
`./zn run --time <seconds+30> -- bash -c 'end=$((SECONDS+<seconds>)); while [ $SECONDS -lt $end ]; do <holds> && exit 0; <failed> && exit 2; sleep 30; done; exit 3'`
(checks: holds = all pass, failed = any failure or the PR closed; merged: holds = MERGED, failed = CLOSED). The prompt names the Bash `timeout` in ms for claude and the measured limit for grok and agent; add an experiment E5 per CLI ("does a 600 s tool call survive?") with the fallback of a shorter `seconds`. The dispatcher counts wall time from the start of the step, not calls, and maps 0, 2 and 3/124 to exit 0, a failure stop naming the red check, and exit 4. Spec cases (dispatch-tiers, promoted): the command has a sleep, an inner deadline below `--time`, and distinct exits 0, 2 and 3 for both `until` values; the prompt names the timeout; the mutants "no sleep", "inner deadline ≥ --time" and "failed folded into 3" are each killed.
Lesson: zz-arch/waiting-steps-show-liveness; zz-test/count-calls-in-poll-loops

### F3 [high] The wait tier is bound to no dispatcher step, against both decided lines
Where: Design, "Waiting" (E2); Problem, "Decided with the user" lines 1 and 2.
Evidence: the user decided "wait is a model activity the dispatcher uses for steps that only poll/babysit (CI, a review, a merge gate)", and "(b) … add a wait entry only if the dispatcher actually has a polling step to bind it to". The design's own E2 finds no polling step and then leaves the gates exactly as they are. `dispatch.luau` `gate()` (prototype lines 291-325) still returns `stop(EXIT.gate)` with "waits for green CI" and "waits for a merge", and `dispatch.next` never returns a `z-wait` action. `z-wait` is reachable only by hand or through the skills' sentence "a wait over 10 minutes goes to `z-wait`". That sentence doesn't save anything either: a lead that runs `./zn dispatch z-wait …` as one blocking shell command is idle in exactly the way it would be running the bounded poll itself, and it adds a Haiku session on top.
Critique: the captured outcome "a long wait or poll runs on the wait tier" and the decided "the dispatcher uses [it] … (CI, a review, a merge gate)" are reduced to a step nothing in the pipeline calls. That is a narrowing with no Scope decision. The tempting fix is more skill text. Skill text still leaves the dispatcher's own gates exiting 4 for a human to rerun.
Consequences: binding the step at the gates gives the chain a new action and needs state ("waited once on this head"), so a rerun doesn't wait forever. It needs a budget setting (a `[dispatch] wait_minutes`, read like `stall_seconds`), and a rule for which gate reasons wait (not draft, not "carries", not unmergeable). Whether the chain should wait on a *human's* merge (the run gate, or `auto_merge` off) is a product choice.
Recommendation: `dispatch.next` returns `{ kind = "step", step = "z-wait", until = "checks" }` when a gate's only reason is "waits for green CI", and `until = "merged"` when it waits for a human merge, if the user chooses that. It does so at most once per gate and head (recorded in the run state), then re-evaluates, and stops with exit 4 only after the wait ran out. Spec cases on `dispatch.next(facts)`: not green → z-wait checks; green + mergeable + auto_merge → merge (no wait); draft or carries → stop with no wait; a wait already recorded on this head → stop 4. Escalate to the user: should the chain also wait on a human's merge of the run PR (options: wait up to `wait_minutes`; never wait, exit 4 as today)? Drop the "waits over 10 minutes go to `z-wait`" rule for leads, or say what it saves.

### F4 [high] The dispatcher/main wiring that delivers "sharp runs every final review" and "spend records the tier" has no criterion, and its design is incomplete
Where: Rules and mutants, last row (`reasoned`); Implementation steps 6-7; Acceptance criteria (no AC covers dispatcher.luau or main.luau); Touched modules.
Evidence: check.sh runs only pure-module specs and doc pins. An implementation that never parses `--final` or `--tier` and never changes `dispatcher.luau` passes AC1-AC13: every new function is reachable from the specs without the dispatcher. The unwritten wiring also meets refusals and gaps the design doesn't mention:
- `./zn spend --phase` accepts only `capture, prep, design-review, deliver` (main.luau:4898), and `commit --phase` accepts only build, code-review and deliver (main.luau:3913). The dispatcher records rows through `./zn spend` (dispatcher.luau:409-424), or as pending rows flushed later (lines 406, 448-469). A `wait` row is refused on both paths.
- Pending rows (`st.pending`, a `Row` with model and no tier) are saved in run state. The tier must be added there too, or flushed rows lose it.
- A model step gets `cwd = worktree(ctx, id)` and `skillPath = "z-nile/skills/{step}/SKILL.md"` (dispatcher.luau:814-817). `z-nile/skills/z-wait/SKILL.md` doesn't exist, and the design doesn't say which worktree a wait runs in, or whether it creates `.worktree/<id>`.
- `dispatcher.resolve(skill, id, project)` (line 320) has no tier parameter. It has three resolve paths and `models.forRaft`, all of which must take the tier.
Critique: these are the outcomes the user sees. The pure parts can be all green while no review ever runs sharp and no row ever carries a tier. c0117's `dispatch-cli.spec` harness with fake CLIs already exists, so these cases can be written and sequestered now. They don't have to be left to the executor's own (unsequestered) specs.
Consequences: a sequestered fake-CLI spec fixes the flag spellings and the `record:` line format, so the docs (AC12) and the printed line must agree with it.
Recommendation: add `acceptance/dispatch-tiers-cli.spec.luau` and an AC14 (the c0117 dispatch-cli harness, in a `.cache/<unique>` fixture), with these cases:
- `zz-review --mode design` starts the fake claude with `--model claude-sonnet-5`, and `--final` with `claude-opus-5-5`;
- `--mode stream --final` is refused;
- the recorded row (direct and pending) carries `tier` cheap or sharp;
- the printed reviewer `record:` line carries `--tier`;
- `z-wait --until merged` against a fake `gh` exits 0 when the state is merged and 4 when it isn't (and 1 or a named stop on CLOSED, per F2);
- a raft resolve with `--final` gives the sharp spec for every CLI.
Specify the wait step's worktree (the lead's own, or none), its prompt source (not a SKILL.md path), and the phase decision (F1).

### F5 [high] The final-round procedure leaves round 5 cheap (or adds a sixth round) and contradicts z-design 5.4's definition and z-raft's one round
Where: Design, "Which round is final"; z-design step 5.4 (SKILL.md:67-72); zz-execute step 7 (SKILL.md:97); z-raft (SKILL.md:41, "One round per grouping"); docs.spec "the round rule names the final round".
Evidence: the design says "when the round rule … would stop, it runs one more round sharp". Walk it:
- Cheap rounds 1-4 are each major. After round 4, z-design 5.4 says run round 5, which "is always final". The rule didn't "stop", so the design's trigger never fires: round 5, a final review, runs cheap. Or, if the author waits for the stop after round 5, the sharp round would be round 6, over the cap of 5 that the design says "counts it".
- Line 72's definition, kept as is ("any round 1 to 4 where it says stop"), makes the cheap round where the rule stops the final one, the opposite of the design.
- docs.spec pins `"the round after which this rule runs no further round"` in z-design, a sentence already on main (SKILL.md:72), so that assertion can't fail today.
- In raft mode, z-raft runs one short round per grouping. Under the design's procedure every raft review becomes two rounds (cheap, then `--final`), or the one round is cheap and final.
- Cost: an issue whose first round would have stopped now always pays a cheap round *and* a sharp round. That is one extra round, and the design doesn't mark it **(prep)** for the user's veto.
Critique: "Sharp runs every final review" is unmet on the round-5 path and on the raft path. The tempting fix ("also run round 5 sharp") still leaves the definition of the final round and z-raft inconsistent.
Consequences: the round rule gets a tier column. Line 72's definition and zz-execute's "the final round's review blocks the merge on a high" must name the sharp final round, and the high-in-final escalation applies to that round.
Recommendation: rewrite both rules in one shape:
- rounds run cheap until either the rule would stop after a cheap round, or the next round is round 5; in both cases the next round is sharp (`--final`);
- from the first sharp round on, every round is sharp;
- the final round is the sharp round after which the rule stops, and round 5 is always sharp and final.
Raft mode: declare `raft` with `tier = "sharp"`, since its one round is always final. Or, if the user prefers, two rounds; put that and the extra-round cost to the user as **(prep)** choices. Pin the new sentences, not the one already on main, in z-design and zz-execute (e.g. "round 5 is always sharp"). Add a docs case that z-raft's raft review is sharp.
Lesson: zz-test/criterion-fails-on-todays-file

### F6 [high] "So the cost per tier shows" has no Design, and the deferral cites a Non-goal that doesn't exist
Where: Design, "Spend records the tier" ("left to zz-stats (listed in Non-goals below)"); Non-goals; Problem bullet 4.
Evidence: Non-goals lists only c0251 and c0142. The design's claim that "`stats` and the board group by the model column as before" is false. `git grep -n '\.model\b' -- z-nile/engine` outside models, ledger and adapters hits only dispatcher.luau's writes (lines 383-985); stats.luau and board.luau never read the model, so nothing shows cost per model today, let alone per tier. Also, the prototype's `resolve` sets `spec.tier = tierOverride or f.tier` even for a table that pins its own model. That contradicts its own `Spec.tier` comment ("nil for a table that pins its own model"). So a pinned Opus (the AC2 fixture `[z-raft.claude] tier = "cheap"` with `model = "claude-opus-5-5"`) would be recorded as `cheap`, and AC2's case doesn't assert the tier.
Critique: the captured outcome is the cost per tier, and the column is only its means. Deferring the report without a `Scope decision` line is a narrowing (zz-review item 11), and a column with misattributed tiers would make any later report wrong.
Consequences: a report needs a reader of the column: `ledger.byTier`, like `byPhase`, and a `./zn metrics` section. That section changes metrics output, and its spec must not pin the existing phase rows, which F1 keeps unchanged.
Recommendation: design and specify `ledger.byTier(rows)` and a "by tier" table in `./zn metrics` (tokens and minutes per tier, rows without a tier as "none"), with a spec case. Or escalate to the user with the options (report here; report in a named follow-up issue, with a Scope decision line). Make `Spec.tier` nil, or a distinct value, when the table pins its model, and add that assertion to AC2's case.

### F7 [medium] Nothing checks that a final round ran sharp, and "only zz-review can be sharp" is vacuous
Where: AC5, AC6; dispatch-tiers.spec "only zz-review can be sharp"; Design, "Which activity runs which tier".
Evidence: `--final` is chosen by the (cheap) author, and no tracker fact records or checks it. An author that never passes `--final` meets every AC. Interactive reviews record their rows with `./zn spend <id> --phase design-review … --note design-review-NNN` (z-design 5.2), and the design adds `--tier` to no skill line, so those rows carry no tier. The AC6 case loops `dispatch.STEPS` and asserts `tierOf(name, nil, false) ~= "sharp"`. But `tierOf` returns `step.tier`, which is nil for every authoring step by construction, so the case passes for any file. Meanwhile `models.parse` accepts `tier = "sharp"` on any skill: a closer `.models.toml` in an issue's folder with `[z-run.claude] tier = "sharp"` is accepted, and `models.forRaft` takes the strongest member spec per CLI (dispatcher.luau:318-338), so one member makes the whole raft's lead sharp.
Critique: "nothing expensive orchestrates" and "sharp runs every final review" live only in skill text.
Consequences: a guard over the final round needs the row to carry the tier on every path, interactive ones included. It needs a cutoff for items reviewed before the change, and a rule for a quota fallthrough (the attempts' tiers).
Recommendation: (a) `models.parse` refuses `tier = "sharp"` on any skill table but `zz-review` (an error naming the key), with spec cases for a root file and a closer file. (b) `./zn status <id> prepared` and `./zn done` refuse, after a cutoff date, when the final round's review spend row (matched by its `--note design-review-NNN` or `review-NNN` commit) doesn't record tier `sharp`. The skills' spend and commit lines pass `--model <id> --tier <t>` for subagent reviewers. Spec cases: a final row with tier cheap is refused, a final row with tier sharp passes, and an item before the cutoff passes.

### F8 [medium] Under the dispatcher, a pinned zz-review model is never used, so reviewRule is dead code
Where: Design, `dispatch.tierOf` and `models.resolve(layers, skill, tier?)`; prototype models.luau resolve (`if tier ~= nil and (f.model == nil or tierOverride ~= nil)`).
Evidence: `tierOf("zz-review", mode, false)` returns `"cheap"` for every middle round. If the dispatcher passes that result to `resolve` as the design says ("resolve with `dispatch.tierOf`", step 7), then `tierOverride ~= nil` holds on every review, and the tier's model replaces a pinned one. The design's "a table that sets its own model keeps it" and "`reviewRule` is kept for a `zz-review` table that pins its own model" then hold only for direct `models.resolve` calls in specs, never in a real dispatch.
Critique: this is an ambiguous precedence that an executor will resolve one way or the other, and no spec decides it.
Consequences: if only `sharp` overrides, a middle round on a pinned table keeps its pin and reviewRule still guards it. That is the c0117 behaviour the Regression guard promises.
Recommendation: the dispatcher passes an override only when `tierOf` says `sharp` (final round, or a sharp mode), and nil otherwise, so the table's own `tier` or `model` decides. Add a fake-CLI case (F4): a closer file pinning `[zz-review.claude] model = "claude-opus-5-5"` gives a middle round that model, and `--final` gives the sharp tier's.

### F9 [medium] Promoted specs pin today's model names and today's CLI set, so every model upgrade and c0175's new CLIs need an override
Where: root-file.spec (`IDS` table, loops over `models.CLIS`), docs.spec (the zz-rules bullet pins `claude-sonnet-5`, `grok-4.7` at xhigh, …); Maintainability ("changing the sharp model is one edit"); Problem bullet "Every other supported CLI … is mapped the same way".
Evidence: root-file.spec asserts `models.id(r.specs[cli]) == IDS[tier][cli]` for every CLI in `models.CLIS`. When c0175 adds `kimi` to `CLIS`, `IDS.cheap.kimi` is nil and the case fails. When Opus 5.6 ships, root-file.spec and docs.spec both fail. Changing the sharp model then means editing `.models.toml`, zz-rules and two promoted specs, with an override chore. Meanwhile the capture's "every other CLI is mapped the same way" gets only "checked at resolve": an error appears only when a step needs the missing tier, which first happens at the final review.
Critique: these promoted cases pin a set, not a rule.
Consequences: the exact names still need checking once, at this issue's check and `done`.
Recommendation: move the exact-name assertions (AC9, AC11, the names in AC12) behind an environment variable that only their check.sh lines set, as f0158 did, so they run at check and `done` and never in the gate. Keep promoted cases that pin the rule: every CLI in `models.CLIS` defines all three tiers in the root file, sharp passes `tierRule`, ranks satisfy wait < cheap < sharp, and no tier model is an alias. That last rule also gives c0175's CLIs their mapping as a gate failure at once, not at a final review.
Lesson: zz-test/promoted-specs-pin-rules-not-sets

### F10 [medium] depends_on and the sibling contracts are unexplained or out of date
Where: frontmatter `depends_on: [c0260, c0248]` (the capture has `[]`); Chore checklist (b); Unknowns, the lessons pass ("neither has a design yet").
Evidence:
- The Design names nothing of c0248 (stacked PR delivery) that c0261 uses.
- With c0260 landing first, "c0260 and c0262 … add `tier = "sharp"` to their `REVIEW_MODES` entries" can't happen for c0260: the field doesn't exist until c0261. c0260's prep says only "run on the review model of the CLI (c0261 decides which is sharp)" (prep-capture-interview-and-idea-review c0260.md:44).
- c0262 does have a design. Its prep (prep-full-force-final-review c0262.md:30, 54 and 69) resolves its final review "through the zz-review table and `models.reviewRule` (… Opus for claude and agent …); c0261's tier names map onto it later". That contradicts c0261's sharp tier on agent (`grok-4.7-xhigh`).
- c0262's depends_on is `[c0260, c0248]`, so nothing orders it against c0261.
Critique: whichever lands second either breaks AC5's promoted "every mode declares its tier" (c0262 first, then c0261's gate) or reddens its own gate (c0261 first, then c0262), and neither document says who adds the field.
Consequences: an order between c0261 and c0262 has to be written in both, and c0262's agent model rule must be reconciled.
Recommendation: drop c0248 from depends_on, or state what c0261 needs from it. Say that c0261 adds `tier = "sharp"` to `idea` (present once c0260 lands) and to `final` if it exists when c0261 lands, and that otherwise c0262 adds it. Write that, and the fact that agent's sharp tier is grok at xhigh rather than Opus, into a note to c0262's prep, or to the user if c0262 disagrees.
Lesson: z-design/quote-other-preps-before-promising

### F11 [medium] The open user question decides eight ACs, and the design contradicts its own reading of decision (b)
Where: Design, first paragraph; Problem, "Decided with the user" line 2; AC10 ("pins no model").
Evidence: the decided line's gloss reads "the per-skill, per-CLI structure of `.models.toml` and `models.luau` stays as it is; … not a refactor". The design removes `model`, `effort` and `rank` from every per-skill table (prototype `.models.toml`: 18 tables), and AC10 makes a pinned model in any of them a failure. The design says the question "is put to the user in the report and is not decided here", yet the issue is `design: reviewed`, and AC1-AC4 and AC9-AC11 depend on the answer.
Critique: an executor can't deliver it if the user answers "no tier tables". z-design step 5.5 sends anything unresolved to the user before `design: ready`.
Consequences: option B changes the specs (tiers-models and root-file) and the Rules and mutants rows, so it is a re-prep of those parts.
Recommendation: escalate to the user before ready, with these options:
- (A) tier tables as designed: one edit per model change, and the file restructured;
- (B) per-skill tables keep their real model names and each carries a `tier` label, which `tierRule` and the alias rule check per label: c0117's file stays, and the model is repeated in 18 tables.
Record the answer as a `Decided with the user` line, and rewrite the gloss so it matches.

### F12 [medium] Restatements of the reviewer rule that the design's sweep misses
Where: Chore checklist, "Restated rules"; AC12.
Evidence: `git grep -noF -e 'review model of the CLI' -e 'review model' -- 'z-nile/skills/*/SKILL.md' z-nile/README.md AGENTS.md z-nile/templates .models.toml 'z-nile/engine/*.luau'` on the prototype (which applies the design's sweep) still hits these lines:
- zz-review SKILL.md:91 (×2): Stream mode, a dispatched stream review is "on the review model of the CLI", against the design's "a `stream` review is cheap";
- zz-execute SKILL.md:60 and :61 (×2): Phase 2B step 7, "a stream review … (the review model of the CLI …)" and "The Phase 4 reviewer still runs on the review model of the CLI";
- zz-rules :171, dispatch.luau :47, models.luau :418 and :436, .models.toml :161 (these describe the sharp tier and are fine once reworded).
README.md:65 says "round one Opus through `claude` or `agent`". AC12 pins only the absence of c0117's one sentence, so these survive. Also, the design says "no alias anywhere", but its interactive rule uses the Agent tool's `model: "sonnet"`, `"opus"` and "the Agent tool's smallest model": those are aliases, which that tool's enum forces.
Critique: the next reader of Stream mode or Phase 2B gets the old rule.
Recommendation: add the zz-review Stream mode and zz-execute Phase 2B step 7 lines to the sweep list. Add docs cases asserting "stream review" plus "cheap" in both, and the absence of "on the review model of the CLI" in zz-review's Stream mode. Reword README:65 or note it as c0251's. State the Agent-tool alias exception, and name `model: "haiku"` instead of "the smallest model".
Lesson: z-design/restated-rules-move-together

### F13 [low] The Usability claims have no case
Where: Usability ("`./zn dispatch --dry-run` prints `tier=`"); Implementation step 4 (`describe` prints ` tier=<t>`); Design ("zz-review … prints it with the model on its `describe` line").
Evidence: no case in dispatch-tiers.spec calls `dispatch.describe`.
Recommendation: one case: `describe` of a resolved sharp spec contains `tier=sharp`, and of a pinned spec contains no `tier=`.

### F14 [low] The E1 probes don't say they ran bounded
Where: Unknowns, E1 (`claude -p --model claude-haiku-5-5`, `agent --list-models`, `grok models`).
Evidence: the record gives results but not the command form. zz-review item 12 asks whether every probe ran through `./zn run --time`.
Recommendation: record each probe as the `./zn run --time <s> -- …` line that ran it, and have Implementation step 1's grok probe (and F2's E5) written the same way.

Candidate lesson for the lead (from F1): an Override or regression search over a module names every alias spelling the specs use to require it (`@znile/engine/<m>` and `@scripts/tracker/<m>`), and the check that re-runs "every spec that reads it" uses the same pattern. Check: does the search pattern cover every alias in `.luaurc`?

Verdict: changes

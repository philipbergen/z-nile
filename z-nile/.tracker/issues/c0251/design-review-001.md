# Review 001: c0251 (design mode)
Inputs: prep worktree `prep-cross-model-review-pool` at 5dec02b7c plus its uncommitted files (`c0251.md`, `check.sh`, the 10 `acceptance/*.spec.luau`, `experiments/E-probes.spec.luau`, `experiments/prototype.patch`, `harvest.md`, the three lesson notes); prototype `proto-c0251` at 9f109ab57 (base ef5a9e9f2), read as evidence (`./zn check c0251` there: 18/18, no tripwire); `./zn capture c0251`; c0306 (active), c0325 and c0260 (prepared), c0332 (new), c0264 (done, its `check.sh`); `lune run z-nile/affected` over the Touched paths; `./zn lessons`.

### F1 [high] The live author reaches only the dry-run. The run, the interactive stamp and every final review use a recorded author that an interactive design or raft review never has
Where: Design outcome 6 ("from `authorread` with `live` = nothing"), outcome 9, prep choice 8, Usability ("a forgotten flag cannot hide a fallback"); prototype `main.luau:4443` (`interactiveFallback` passes `""`), `dispatcher.luau:829`; the prototype's zz-review "Interactive pick" ("otherwise it runs `./zn dispatch zz-review <id> --mode <m>` for it", with no `--author`); c0325 `authorship.STEPS.final = { "idea", "design", "build" }`, with `live` placed on the mode's first step; `acceptance/interactive.spec.luau:465`.
Evidence:
- The design writer's row is `./zn spend <id> --phase prep`. z-design step 6 writes it "right after the prep PR is opened", which is after the step-5 review. z-raft's `raft-prep` row is also written at PR open (c0325's table). This prep's own `spend.d` holds no `prep` row. So when an interactive lead runs `spend --phase design-review --model X`, the stamp's plan has no row and no live author, and `design-challenge` has no `author` key. The writer becomes `[roles.design]`'s first choice, `claude-opus-5-5`, provenance `assumed via role`.
- **False flag.** A lead on `claude-fable-5-2` runs `--dry-run --author claude-fable-5-2`, which picks Opus. The lead runs an Opus subagent and types `--model claude-opus-5-5`. The stamp then writes `Fallback: the model that wrote the text ran the review (claude-opus-5-5); author assumed via role`.
- **Missed fallback.** The same Fable lead instead runs a Fable subagent, a true same-model review. Against the assumed Opus writer the stamp's plan puts the Fable member first in tier 1, so `interactiveReason` returns nil and nothing is flagged.
- **The dispatched run.** The run that zz-review tells the lead to start carries no `--author`, so it orders against the same assumed Opus writer. For a Fable-written design it picks Fable, unflagged.
- **Unmarked items.** c0248, c0250 and c0251 are unmarked and record no model on build commits, so the author of their layer code reviews is an assumed Sonnet. An Opus-built layer reviewed by an Opus subagent is never flagged.
- **Final reviews.** For `--mode final`, c0325 puts `live` on the `idea` step. `dispatcher.plan` keeps only the writers of the last step (`build`), so `--author` and `ZN_MODEL` are dropped for every final review.
- **The specs.** AC10's fixtures seed a `prep` row whose model equals the role's first choice (Opus on both sides), so no case can tell which source the stamp read. AC9 tries `--author` in design mode only.
- **Two walks.** By the Prototype notes, the dry-run and the run read origin's `.models.toml` and the stamp reads the working tree's. In a layer that edits `.models.toml` (c0251's own, c0175's), the two plans differ.

Critique: the interactive CLI is the main way into z-work, and on that path the derived stamp is computed against a different plan from the pick. The tempting fix is to make the lead run `spend --phase prep` before the review. That writes a second `prep` row, which double-counts the prep's lines (step 6 says once), and it still does nothing for final reviews.
Consequences: a new input on `spend` and `commit` has to be validated the way `--author` is, and it is the honour system's: without it the stamp stays `assumed` and the reason says so. The skills that show these commands restate it. The plan has to come from one `.models.toml` walk.
Recommendation:
- Carry the live author to every consumer of the plan:
  - `./zn spend <id> --phase design-review --note … --model <reviewer> --author <lead id>`;
  - `./zn commit --phase code-review --model <reviewer> --author <lead id>`;
  - zz-review's run line: `./zn dispatch zz-review <id> --mode <m> --author <its model id>`.
- `--author` is validated by `ledger.isModel`. When it is absent, behaviour stays as now, and the reason says `assumed`.
- In `dispatcher.plan`, give `live` to the mode's last step (the step c0251 reads), so a final review takes it.
- Build the stamp's plan from the same walk as the dry-run, or name in the reason which walk was used.
- Restate the commands in z-design 5.2, z-raft, zz-execute Phases 4 and 5, and the zz-rules rows, and pin them in docs.spec.
- Cases:
  - (a) No `prep` row, design role Opus, `--author claude-fable-5-2`: a typed Fable is flagged, a typed Opus is not.
  - (b) The same without `--author`: as today, and the reason says assumed.
  - (c) `--mode final --dry-run --author X` changes the order.
  - (d) A dispatched run with `--author` orders by it.
- One Rules row per case, with the mutant "the stamp ignores `--author`".

Lesson: zz-test/pin-call-site-arguments; z-design/results-land-on-every-path

### F2 [high] c0260's prepared idea loop pins a hard exclusion and stop that the "never blocks" rule must remove, and the design never mentions it
Where: Design outcome 5 (the idea path, `authors = {wrote}`), Interactions with other items (no c0260), Regression guard `Overrides:`, chore checklist "Existing work".
Evidence:
- c0260 is prepared, and R-vision starts only after it is done (Decided Q2 2026-11-11, README line 190). It adds `Drive.exclude` to `modelstep.drive`: "Each challenge starts without any try whose model is in the set, fallbacks included, and fails with main's message when none is left" (c0260.md:109, 120).
- Its sequestered `acceptance/loop.spec.luau:432`, "AC12: the model that wrote a text, a fallback included and whatever its effort, never challenges it", asserts that "with grok gone the second challenge fails rather than let kimi challenge its own revision" (lines 449-459).
- c0251's design hooks `order` into main's pre-c0260 `cmd.idea` (~7007) and leaves that exclusion and stop alone. Once both land, the idea challenge still blocks when only the writer's model is left. That goes against Decided Q2 (2026-11-15, "Soft, never blocks"), and the picker never sees a tier 3 try.
- If the executor removes the exclusion to meet AC12 and Q2, c0260's promoted `loop.spec` goes red, and no Overrides line names it.
- The loop has several writers per run (the draft and each revision), but the design passes one (`{wrote}`). A kimi revision is then tier 1 for the next challenge.

Critique: it is an unnamed override and a prepared design that disagrees with this one, so the executor meets a different `cmd.idea` with no guidance.
Consequences: c0260's label "the model that wrote a text … never challenges it" stays in its done `check.sh` while the case changes. The idea path's flag ties to F3.
Recommendation:
- Design the idea path on c0260's loop: the exclusion set becomes the picker's `authors` for each pass (the draft's writer and every revision's), the "none left" stop goes (tier 3 runs last), and a pass whose challenge attempt was tier 3 records its fallback (F3).
- Name `z-nile/tests/acceptance/c0260/loop.spec.luau` (that AC12 case) on the Overrides line, with what it still pins: the writer is tried last and never before another line.
- Add c0260 to Interactions and say which order the two land in.
- Add a Rules row and cases: a kimi reviser is ordered last; with every other line failing, kimi challenges and the pass is flagged.
- Rerun the existing-work search over every open `acceptance/` folder for `exclude`, `never challenges` and `only model left`, and name the search so it can be rerun.

Lesson: z-design/quote-other-preps-before-promising; z-design/new-rules-migrate-existing-work

### F3 [high] Idea challenges and stream reviews never record or flag a fallback, though the captured Problem asks for it on every review
Where: Problem ("Every review records its model and whether it was a fallback; the board flags fallback reviews"), prep choice 2, outcome 5 ("Idea reviews stay unstamped"), outcome 8, AC12; `acceptance/dispatch-pool.spec.luau:709`; prototype `boardview.reviewPaths` (`boardview.luau:159`), `dispatcher.luau:1272` (`not streamDir`).
Evidence:
- **Idea challenges.** AC12's case runs a kimi-drafted idea with Opus refused, so kimi challenges its own draft. That is tier 3, the exact writer. The case then asserts `has(ideaReview, "Fallback:") == false`. Nothing else records that the challenge was a fallback (the idea spend row records the model only).
- **The board.** The board reads only `design-review`, `review` and `final-review` files.
- **Stream reviews.** The dispatcher stamps a stream review (c0306 stamps every mode), but `reviewPaths` leaves `stream-review-*` out. A tier-3 stream review then carries a `Fallback:` line that nothing shows: AC11's own Haiku-written layer, with kimi and grok out. A stream review is also never superseded (`not streamDir`).
- No Scope decision or Decided line exempts either kind.

Critique: two of the review kinds the Problem covers are dropped from "records whether it was a fallback" and "the board flags it", and a spec pins the drop.
Consequences: an idea review file that carries `Fallback:` but no `Model:` is a new shape. c0306 never judges idea reviews, and c0260's `idea.parseReview` must ignore the line.
Recommendation:
- Record and flag both kinds:
  - the tool writes `Fallback:` into the idea review file it writes, and zz-review's "writes `idea-review-001.md` from this reply, unchanged" gains "except the tool's `Fallback:` line";
  - the board reads idea-review and stream-review files;
  - the note names what re-reviews each kind (for an idea, the next `./zn idea` pass, numbered on, as in c0260; for a stream review, a new round, which today's one-round rule refuses).
- Flip AC12 to expect the line, and add a board case per kind.
- Or escalate to the user: exempt idea and stream reviews from the record and the flag, written as a Scope decision. The cost: an idea challenged by its own writer, or a stream review run by the layer writer's own line, stays invisible.

Lesson: z-design/never-narrow-captured-scope

### F4 [high] Unmarked items carry stamped rounds, but the design treats them as stampless: they rotate on the author only, and their flagged rounds can't be superseded while the board flags them
Where: prep choice 3 ("An unmarked item has no stamped prior"), Prototype notes (`reviewfiles.priors` skips an unmarked folder), outcome 5 (supersede "marked items only, as c0306"), outcome 8; `acceptance/priors.spec.luau:152` (and X5); prototype `reviewfiles.luau:55`, `dispatcher.luau:1272-1278`.
Evidence:
- c0306 stamps in every item. Its dispatcher stamps each review it files, in any mode, unless the reviewer wrote its own `Model:` line in an unmarked item (prototype `dispatcher.luau:1303-1309`). `spend` and `commit` with `--model` also stamp in an unmarked item (c0306 outcome 3). So the premise of prep choice 3 is false.
- **(1) Priors.** Priors from unmarked folders are skipped, and X5 pins the skip. "And from the previous round's reviewer, so rounds rotate" therefore fails for every item claimed before c0306 lands. That includes R-vision's own c0248, c0250 and c0251, all unmarked: their layer code reviews, filed in their issue folders (c0248), rotate on the author only.
- **(2) Re-review.** `boardview.fallbacks` reads no mark, so the board flags an unmarked item's `Fallback:` round. But `supersedes` requires `markedFolder`, so the command on the board is refused there with "one round … there is no second round".
- No decision line narrows the outcome.

Critique: a prep choice that rests on a false premise leaves a captured outcome only partly true for most items in flight on the landing day. It also prints a way out that is refused.
Consequences:
- c0306's one-round rule for unmarked items gains a flagged-round exception. Its refused-round exception stays marked-only.
- A reviewer-written `Model:` line in an unmarked item can only reorder the picks, never cause a flag.
- A reviewer-written `Fallback:` line there would at most allow one more round.
Recommendation:
- Count the stamped rounds of unmarked folders as priors.
- Let a flagged newest round be superseded in every item, and say so in zz-review's Output file and in the skills' one-round sentences.
- Cases:
  - an unmarked issue with a stamped Opus design round gives priors `{claude-opus-5-5}`;
  - an unmarked item whose newest round is flagged files `NNN+1`;
  - an unmarked unflagged round is still refused.
- Invert X5 and the AC4 unmarked case.
- If unmarked items are to stay out, escalate to the user, and the board must then not flag them. The cost: every pre-c0306 item's fallback reviews stay invisible, R-vision's layers included.

Lesson: z-design/never-narrow-captured-scope

### F5 [medium] The board's re-review command does not work where a person reads it, and nothing says what follows
Where: Design outcome 8, prep choice 11; prototype `board.html` `fallbackNote`, `dispatcher.luau:911`.
Evidence:
- The note prints `./zn dispatch zz-review <id> --mode <m>`. The board is built in and read from the main checkout, and there the dispatcher raises "zz-review runs in its author's worktree, not the main checkout".
- By the time a person reads the board, a flagged design round has usually landed with its prep, so the prep worktree is gone.
- c0306 already found that a new design round, once answered, changes the design record of a grouped or readied issue. `ready` then refuses it until the member is unfolded, re-prepped and folded back (c0306.md outcome 5, the refused-round route).
- The note gives no next step (who answers `design-review-002`, the refute, the harvest, the PR) and leaves `<m>` for the person to work out.
- `fallbackReviews` is also computed for done issues and rafts, where a re-review changes nothing.

Critique: the outcome "so the human can ask for a cross-model re-review" fails for the common case when the printed route is followed literally.
Consequences: the board needs each item's state (it has it) and the kind of each flagged file.
Recommendation:
- Render the route that works for each state, as c0306's refusal does:
  - preparing: in its prep worktree;
  - prepared and ungrouped: `cd "$(./zn worktree prep-<slug>)"`, then dispatch, answer and land by PR;
  - grouped or readied: the unfold, re-prep and fold route (a raft of several issues then needs a new coherence review);
  - an active layer: in the raft worktree, before `done`;
  - done: flagged as history, with no command.
- Fill `<m>` from the file's kind.
- Cases: the note for each state, and one that follows the printed route literally on a prepared issue and gets `design-review-002.md` filed.

Lesson: z-design/refusals-name-a-way-out-that-works

### F6 [medium] The README keeps the old drop rule marked `*exists*`, and the planned rewording breaks c0264's done check, which pins the label places
Where: Design outcome 10, Interactions c0264 ("edits its `c0251-reworded` pin"); `z-nile/README.md:108`, `:114`; `docs.spec` AC13's README case; `z-nile/.tracker/issues/done/c0264/check.sh` (`truth`, AC6 `vocabulary`).
Evidence:
- **Line 108.** It is marked `*exists*` and still says "`idea-challenge` and `code-review` name the role that wrote the text as their `author`, which drops that model; `design-challenge` and a raft's review run on the same model as their author". It also says "Every review runs on an expensive role", while c0251 adds the cheap `stream-review` role. The prototype leaves line 108 as it is, and docs.spec does not read it.
- **Line 114.** The prototype rewrites it as "`*exists* (c0251)`; a role's `author` only stands in …", which removes the line's second, bare `*exists*` label. c0264's done `check.sh` AC7 pins the label places of "Reviews by different models" as `c0251` then `-`, so it reports "label places differ" once c0251 is done.
- **The pin.** No `c0251-reworded` pin exists in `tests/acceptance/c0264` (grep). The pin is in that done `check.sh`, which may not be edited.
- **c0264's AC6.** It requires the words `Every review runs on an expensive role` to stay.

Critique: these restate the rule c0251 changes and stay false. The obvious fix, deleting line 108's phrase or merging the labels, turns c0264 red.
Consequences: the rewording must keep c0264's words and its two labels.
Recommendation:
- Reword line 108 so it keeps `Every review runs on an expensive role` as a substring (for example "…, but a stream review, which runs on `stream-review`"), without the drop and same-model clauses.
- Keep exactly two labels in "Reviews by different models": `*exists* (c0251)` and one bare `*exists*`.
- docs.spec pins that the removed clauses are absent, and the label count.
- The Regression guard names c0264's `check.sh`, and the executor runs `./zn check c0264` once c0251 is in `done/` (before that, its AC7 state check is red for c0251 by construction).
- Replace the "`c0251-reworded` pin" sentence with what is true.

Lesson: z-design/restated-rules-move-together

### F7 [medium] The AGENTS.md outcome of the confirmed Idea moves to c0332 with no decision line, and c0332 does not wait for this rule
Where: Idea, "The rules change to match" (confirmed 2026-11-11); Solution's last bullet; prep choice 10; chore checklist "Restated rules"; AC13 and its `check.sh` AGENTS.md diff.
Evidence:
- The confirmed Idea says the rule changes in "every other place that states it, including AGENTS.md's pin of design and code reviewers to Opus 5.5". The design gives AGENTS.md line 7 to c0332, and AC13 forbids changing it. No Scope decision or Decided line records the move.
- c0332 (status new, design draft) depends on c0293 and c0306, not on c0251. Its Solution says a reviewer subagent "runs on the model `.models.toml` names for its review role", not the pick.
- Every session loads AGENTS.md. Until c0293 and c0332 land, it tells a lead that reviewers are pinned to Opus 5.5, which for an Opus-written design is the tier-3 fallback.
- The checklist's Restated rules bullet omits AGENTS.md.

Critique: a restated rule is left steering leads the wrong way, with the ownership change unrecorded.
Consequences: either choice below touches another item's scope, which is the user's call.
Recommendation: escalate to the user:
- (a) c0251 rewords AGENTS.md line 7 to point at zz-review's pick, coordinated with c0293's rewrite, which is being prepared, and AC13 then pins the new line. Cost: c0293 and c0332 rebase on it.
- (b) A `Decided with the user` line hands it to c0332: c0332 gains `depends_on: c0251`, and its Solution names the pick. Cost: AGENTS.md keeps steering leads to Opus reviewers until c0293 and c0332 land.

Either way, the Restated rules bullet names AGENTS.md.

### F8 [medium] The "cheap" fallbacks of `stream-review` are an unresolved unknown against the user's Q4 ruling
Where: prep choice 12, outcome 7 (`[roles.stream-review]`), AC18.
Evidence: Decided Q4 (2026-11-15) says "a new `[roles.stream-review]` on a cheap model whose fallbacks are cheap families". The design gives it `fallbacks = ["kimi", "grok"]`, that is `kimi-code-k3.1-pro` (one of the sharp review kinds c0306 judges) and `grok-4.7`. It says itself that "whether kimi and grok are cheap per token is not determined". There is no experiment, no pass/fail question and no fallback, and AC18 pins the guess.
Critique: an unknown that decides whether a user ruling is met is left open and then frozen by a spec.
Consequences: if either fails, the role's fallbacks change, or a stream review has none while Haiku is out, which touches "never blocks".
Recommendation:
- Run an experiment now. Pass/fail question: is each CLI's price per million tokens for that model, at `medium`, within a stated bound of Haiku's (from the published price list or a measured run's cost)?
- If either fails, escalate to the user with the options: keep it; drop it until opencode lands, saying what a stream review does when Haiku is out; or use another cheap id.
- Record the answer as a Decided line and in prep choice 12.

### F9 [medium] `[roles.raft]` is both z-raft's authoring role and the raft-review role, so the review pool changes how rafts are authored
Where: outcome 7 (`rotate = true` and `pool = ["fable"]` on `raft`), outcome 4, chore checklist "No behaviour change", Overrides (c0117 `models.spec`: "5 tries for `z-raft`").
Evidence:
- `roleFor("zz-review","raft")` is `raft`, the role `./zn dispatch z-raft` authors with. With the pool, z-raft tries Opus, Fable, kimi, grok, agent, which the c0117 override records.
- Q4 says "authoring keeps its role's order … and has no rotation", and the checklist says every authoring role tries "exactly as today".
- Outcome 4 rotates any role with `rotate` and never names the step. The prototype skips z-raft only because its mode is nil (`dispatcher.plan` returns no rotation when `reviewMode == nil`).
- No case pins that a z-raft step is never reordered. The mutant `reviewMode = mode or "code"` for every step survives.

Critique: an undisclosed authoring change against a user ruling, and a design text that does not confine rotation to reviews.
Consequences: a separate role moves c0306's F6 skip. At `xhigh`, grok would no longer be refused for raft review, which changes this issue's AC5 case "grok at effort high is never started" and any c0306 raft-mode case.
Recommendation:
- Give raft-mode review its own role, `[roles.raft-review]`, returned by `roleFor("zz-review","raft")`, and leave `[roles.raft]` as it is. zz-review's "Raft-mode review uses the raft role" changes, and the c0117 "5 tries for z-raft" override goes.
- Or escalate to the user to accept Fable as z-raft's second try, written as a Decided line.
- Either way, outcome 4 says only `zz-review` steps and the idea challenge rotate. Add a case: a z-raft step on a role that carries `rotate` is tried in toml order, whatever the recorded writer.

### F10 [medium] Rules with no row or no case: the idea path, the interactive stamp's mode mapping, and raft-mode rotation
Where: Rules and mutants, Test plan; prototype `main.luau:6605` (`spend`: a raft folder becomes `raft`), `main.luau:4646` (`commit`: `final-review-NNN.md` becomes `final`); `acceptance/dispatch-pool.spec.luau:624`.
Evidence:
- (1) AC12, the idea challenge through the picker, has no row, so no mutant was run for it (for example, `ordering` not passed to `run`).
- (2) interactive.spec stamps only issue-folder design reviews and raft-folder `review-NNN.md`. A mutant that maps every `spend` to `design`, or every `commit` to `code`, survives. A raft-folder coherence review would then take the members' design writers as its author.
- (3) Raft mode never runs with `rotate`: dispatch-pool's `[roles.raft]` has none ("the raft role has no rotate"), while the root's has. So the raft-prep writer and the raft-mode priors (members' design reviews, the raft's own coherence reviews) are untested end to end.
- (4) `describe`'s `member=<name>` is in the design, but no case reads it.

Recommendation: add a row and a case for each, mutation-run them on the prototype, and record the outcomes in E11.
Lesson: zz-test/seed-every-enumerated-case; z-design/spec-design-correspondence

### F11 [medium] Previous rounds compare round numbers across folders that c0248 numbers independently
Where: outcome 3 ("then highest round number"), `acceptance/priors.spec.luau:146-149`, Interactions c0248.
Evidence:
- `priorsOf` takes "the highest rank, then the highest round number at that rank, across all the folders". The spec pins "a member with a newer round at the same rank wins over the others' older ones": c0114's `review-002` beats c0110's `review-001`.
- c0248 numbers each issue folder's layer reviews from 001, so round numbers in two member folders say nothing about which round came last.
- Example: in a raft where layer 1 was re-reviewed (`review-002`) and layers 2-5 each have `review-001`, a final review's "previous round" is layer 1's re-reviewer alone, and layer 5's reviewer is ignored.
- The same holds for a raft review over the members' `design-review-NNN`.

Critique: the rotation away from "the previous round's reviewer" picks by an accident of numbering.
Consequences: a union over many layers can put every line in tier 2, and then the role's order decides.
Recommendation: define the previous round of a raft-level review explicitly. First take each folder's newest round at the highest rank present. Then take either all of them (a union) or the top layer's (by the raft's Order, which c0248 makes the stack order), and say which. Pin it with a case where two member folders hold different round numbers.

### F12 [low] Document accuracy
Where: Touched modules, Affected specs, chore checklist and AC14, Implementation steps, Prep choices.
Evidence:
- **Touched modules.** It lists `tests/acceptance/c0117/docs.spec.luau` and `tests/tooling/dispatch-texts.spec.luau`, which neither the Overrides line nor the prototype changes. It omits `tests/tooling/idea.spec.luau`, `tests/acceptance/c0306/dispatch-review.spec.luau` and `tests/acceptance/c0325/match.spec.luau`, which the Overrides line changes. Spend attribution and `affected` read this list.
- **Affected specs.** The section holds an instruction, not the selector's output (z-design step 3).
- **"Exactly as today".** The chore checklist and AC14 say a role without `rotate` tries "exactly as today". But `models.tries` loses the author drop for every role, so a role with `author` and no `rotate` now runs the author's model in toml order, unflagged.
- **Implementation step 1.** It says "AC1 to AC15", but there are 18.
- **Prep choices.** They run 1-10, 12, 13, 11.

Recommendation: align Touched modules with the Overrides line, paste the selector's output, state the drop's removal for roles without `rotate` (or keep tiers for any role with `author`), and fix the numbering.

Harvest: the three notes in `harvest.md` (count pins, fixture configuration as existing data, chained `--run` calls) are rules another raft could fail, not restated findings. No finding.

Verdict: changes

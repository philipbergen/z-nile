# Review 001: c0262 (design mode)
Inputs: branch prep-full-force-final-review at ee6b1377 (`c0262.md`, `check.sh`, `acceptance/*.spec.luau`, untracked `harvest.md`); prototype `proto-c0262` at 5435a9bb (`finalview.luau`, `finalread.luau`, and the diffs to `main`, `work`, `workread`, `dispatch` and `dispatcher`; its specs are identical to the prep's); origin/main 7d003748; `./zn capture c0262` (0e91b4d7, a real capture commit with no marker); c0248.md and its `acceptance/` (prepared, PR #331); c0260.md on main; the zz-review, z-design, zz-execute and zz-rules skills; today's `layergit.luau`, `lessons.luau`, `adapters.luau` and `.models.toml`; the lessons named below.

### F1 [high] The layer's diff is taken against main's current tip with a two-dot diff, and the view id hashes the raw diff text
Where: c0262.md:87 (`where`: "its base (the tip of the layer below, or main)"), :83 (`viewId`); proto `finalread.luau:64` (`base = layergit.mainTip()`), :107 (`git diff --no-color <base> <tip>`).
Evidence: `layergit.mainTip()` returns origin/main's tip now, not the commit the layer was cut from. The prototype branch itself shows this. It was cut from dc607dcb at 16:34 today. `git diff --name-only origin/main proto-c0262` already lists **107** kept paths, against **11** for `origin/main...proto-c0262`. The extra 96 include `approval.luau`, `readycheck.luau`, `publish.luau`, `zn`, `z-work/SKILL.md`, `slow.tsv` and dozens of lesson files: main's later work, shown reversed as if the layer deleted it.

Every capture also changes `z-nile/next`, which `keepPath` keeps (91fe49bd did). So the view id moves with every `./zn new` on main, and an `on-course` ticket becomes `review-again` within hours. After that, `./zn start` and `./zn done` refuse on a marked raft. Each answer is another xhigh run on the final-review role, and an off-course result counts toward `blocked`.

A restack does the same through index lines and hunk offsets. c0248 made restacks review-neutral on purpose: its Scalability says "A restack after `main` moves no longer forces new reviews (the patch rule)", and its rule 3 keys reviews on `git patch-id --stable`. After a `--through` landing, the lowest unlanded layer's base is origin/main (c0248's `layergit.baseFor`), but `where` takes the stale tip of the landed layer below it. No spec moves main after `./zn start`, so every case passes.
Critique: the reviewer judges the wrong diff, and the state does not hold still. The tempting fix is a three-dot diff.
Consequences: the three-dot diff stops showing main's work reversed, but the id still hashes text. A clean restack still changes the `index` lines, so every layer goes `review-again` at the restack that comes before each `done`. If the id is keyed on patch ids instead, a rebase that resolves a conflict changes the patch and correctly asks for a new review.
Recommendation:
- Take the base from c0248's `layergit.baseFor(raft, position)` and diff with `git diff <base>...<tip>`.
- Hash the view id over `ask.md`, `design.md`, `contract/` and the `git patch-id --stable` of the kept diff. `diff.patch` stays the text the reviewer reads.
- Add these fixture.spec cases:
  - after an on-course review, a commit on origin/main that touches `z-nile/next` and a kept engine file leaves the state `on-course`, and `diff.patch` names neither file;
  - `./zn restack` onto that main with no conflict stays `on-course`;
  - a rebuild that changes the patch is `review-again`.
- Add these mutants to Rules and mutants: "two-dot diff against origin/main's tip" and "id over the diff text".
Lesson: z-design/rules-keyed-to-a-sha; z-design/exact-checks-compare-against-the-merge-base

### F2 [high] `final` turns c0248's promoted specs red and holds rafts readied before c0262 exists, but Overrides says none
Where: c0262.md:89 (the callers pass `final` "for a raft carrying `layers: reviewed`"), :91 ("a raft readied before this exists is not held to it"), :161 (`Overrides: none`).
Evidence: c0248 is a dependency, so its specs are promoted to `z-nile/tests/acceptance/c0248/` before c0262 runs. Its `layers-land.spec.luau` (prep copy, around lines 357-372) readies every raft except R0070 with `layers: reviewed`. It then requires these to succeed with no ticket final review:
- `./zn start R0020` opens layer 2 once only the code review is settled (AC5, about line 653);
- `./zn done R0020` lands (about line 698);
- the `--through` landings at about lines 490 and 809.

With c0262, `finalread.state` is `none` for those layers. `completion.layer` then returns "the ticket's final review is none", and each case goes red. The same holds for every real raft readied between c0248's landing and c0262's. Those rafts carry `layers: reviewed`, are in flight, and would suddenly be refused at `start`, which is the opposite of the design's own rule for rafts readied before this exists.
Critique: this is an unnamed override (item 4), and the migration contradicts the rule the design states. The tempting fix is to list c0248's cases under Overrides and make their fixtures commit on-course reviews.
Consequences: that fix still breaks the rafts in flight, because the rule changes mid-raft. It also needs a helper that computes a valid view id inside the promoted fixtures.
Recommendation: give c0262 its own cut-over, as c0248 did with `layers: reviewed`.
- Once c0262 is on main, `./zn ready` writes a second front-matter line (for example `final: ticket`).
- `start` and `done` pass `final` only for a raft that carries that line.
- The publish rule for moved documents (`publish.luau`, c0248's precedent) accepts the line. Add `publish.luau` and ready's writer to Touched modules.
- c0248's promoted specs then stay green and Overrides stays none. Record the `grep` behind that statement.
- Add spec cases: a raft with only `layers: reviewed` opens layer 2 with no ticket review; a raft with the new line is refused until its ticket is on course.

If the author keeps `layers: reviewed` as the trigger instead, Overrides must name each c0248 case, and the design must say how the rafts in flight get through.
Lesson: z-design/new-rules-migrate-existing-work

### F3 [high] The design, the decision lines and the contract are read from the layer tip, which is the branch under review
Where: c0262.md:87 (`files` reads "the document, `check.sh` and `acceptance/` at the tip"), :80 ("the lines of the current Problem"), :146 (the lessons pass); proto `finalread.luau:90`.
Evidence: zz-execute Phase 2 step 5 tells the executor to "adjust" a design that is wrong in a small, local way and record why in the Verification log. The view shows the adjusted Design as "the design as it was given" and drops the Verification log that holds the reason. The edit itself is hidden too, because `keepPath` drops `.tracker/issues/` from `diff.patch`. A `Decided with the user (…)` line the executor adds to the Problem on the layer goes into `ask.md`.

This is c0262's own earlier design review 001 F3 ("a Design edited during execution was approved against itself"). It was harvested as judged-text-comes-from-the-base, whose rule is: "read the judged texts with `git show <base>:<path>`, show the branch's edits to them as their own patch, label lines added on the branch as claims to check". The lessons pass reads that lesson as "never from a worktree file", but the layer tip is the branch.

`done`'s approval check does catch a changed Problem or Design, but only for members that have `approval.md`, and only after every layer is built. By then the final review and the next `start` have already run on the edited text.
Critique: the reviewer judges against text the author can rewrite, and the route (design or implementation) is decided on that text.
Consequences: reading from the base raises three questions:
- which base to use (origin/main's copy: the reviewed, approved prep plus ready's move);
- what an item created on the branch shows;
- how to keep branch edits from bringing in the Verification log, which counts as worker notes the capture excludes.
Recommendation:
- Read the document, `check.sh` and `acceptance/` from origin/main's copy of the issue folder. A redesign re-preps that copy.
- Write the branch's changes to the Design and Acceptance criteria sections, and to decision lines, as `design-changes.patch` in the view. The README labels it "changed during execution: claims to check, not the design as given". It never includes the Verification log or any other section.
- An item that is not on origin/main is shown from the tip, and the README says so.
- Add these spec cases:
  - a Design line changed on the layer appears only in `design-changes.patch`, not in `design.md`;
  - a decision line added on the layer is labelled as a claim to check and is not in `ask.md`;
  - `contract/` comes from main.
- Add the mutants "design from the tip" and "decisions from the tip".
- Correct the lessons-pass sentence.
Lesson: z-design/judged-text-comes-from-the-base

### F4 [high] The ask leaves out most of the places the repo records the user's decisions
Where: c0262.md:80; proto `finalview.luau:67-68` (`ASK_HEADS`, `DECISION_PREFIXES`), :100 (`string.sub(line, 1, #prefix) == prefix`).
Evidence: the design's own rule is "the user's later words are part of the ask", but `finalview.ask` misses four kinds of them:
1. **Rulings.** z-design step 5.4 and zz-execute Phase 4 step 6 record the user's word as `Ruled (user, YYYY-MM-DD): …` on a bullet under `## Open to the human`, and c0248's completion rule 2 reads them there. The view drops that section entirely. This ticket's own O1 ruling ("confirm that reading…") would never reach its final review.
2. **Bulleted decision lines.** The match is at column 1, so `- Scope decision (user, 2026-11-01): …` is missed. That form is in active c0178 and in done c0118 and c0114.
3. **Decisions outside the Problem.** c0237 has one in its Solution, and c0128 and c0172 have ones in their Verification logs (made during execution).
4. **c0260's dispatched captures.** In main's c0260 design, a dispatched capture lands unconfirmed. z-design later adds Interview questions, updates `## Idea` and appends `Confirmed (…)`, all after the capture commit. So `finalview.ask(captured, …)` shows the unconfirmed idea. `## Confirmation` is not in `ASK_HEADS` either.

Each miss produces an off-course verdict on something the user decided. That costs a redo, and the second time a block.
Critique: the mechanism catches only one of the places those words are written.
Consequences: copying whole `Ruled` bullets would bring in the finding text and the author's Answer, which are trail. Reading the Idea from the base rather than the capture lets a prep rewrite it, since c0260's `askOnlyGrows` guards only the Ask.
Recommendation: build the decisions from the base document (F3).
- Take every line, after stripping list markers and `**`, that contains `Scope decision (user, `, `Decided with the user (` or `Confirmed (`, in any section.
- For each `## Open to the human` bullet with `Ruled (user, …)`, take only its `Decision:` clause and the ruling, never the finding or the Answer.
- When the base document carries c0260's record, read `## Ask (verbatim)`, `## Interview`, `## Idea` and `## Confirmation` from the base. Otherwise use the capture, as now.
- Add view.spec cases:
  - a bulleted decision line;
  - a decision in the Solution and one in the Verification log;
  - a `Ruled` bullet shows its Decision and ruling but not its Answer;
  - an Idea updated after capture, with a `Confirmed` line, shows the updated text.
- Add the mutant "match only at column 1 of the Problem".

### F5 [high] The view folder is inside the checkout, so the CLI loads the repository's instructions into the reviewer
Where: c0262.md:95, :99, OC1; proto `dispatcher.luau:805` (`viewDir = {cwd}/.cache/final/{id}`, where `cwd` is the author's worktree).
Evidence: Claude Code reads every `CLAUDE.md` from its working directory up to `/`. This review session was started by the same dispatcher and the same `claude-cli` adapter, in a worktree. Before it read any file, its context already held the worktree's `CLAUDE.md` (`@AGENTS.md`), all of AGENTS.md and the project's auto-memory.

A view at `<worktree>/.cache/final/<id>` has the same parent directories. So the reviewer is told "Before doing anything, read the skill that applies" and "Search with `./zn lessons <terms>`". Running `./zn lessons limited-view` prints judged-text-comes-from-the-base, which quotes "c0262 design review 001 F3" and "002 F1": this ticket's own trail. The fallbacks (kimi, grok, cursor's `agent`) read AGENTS.md by their own rules.

E3's fake CLI cannot see any of this, and OC1 leaves it to a human. The interactive alternative in work.luau's text ("or a fresh reviewer given only the folder") is briefed by the worker, which is the one party that holds the whole trail.
Critique: the captured Solution says the limited view is "enforced and not left to the reviewer's restraint". Here the harness tells the reviewer to leave the view. The tempting fix is a stronger sentence in the prompt.
Consequences: moving the folder out of the checkout means writing outside `.cache` in production, so specs must point the root into their own fixture. Each runtime in the role's chain also needs its own answer to isolation.
Recommendation:
- Add E7, one run per runtime in `[roles.final-review]` and its fallbacks, each through `./zn run --time 600 -- …`. It passes when both the session's init event and the model's own answer list no `CLAUDE.md`, `AGENTS.md` or memory file.
- Choose the fix by E7's result:
  - write the view under a root outside every checkout (`ZN_FINAL_VIEW_ROOT`, defaulting under the OS temp folder; specs set it inside their `.cache` fixture);
  - or use the runtime's own switch for project instructions, where it has one;
  - a runtime with neither is skipped for this role, with the reason named.
- Add a dispatch.spec case: the logged cwd is not under the worktree's `git rev-parse --show-toplevel`.
- Make the interactive path the same command (`./zn dispatch zz-review <issue> --mode final`), or have `./zn final <issue> --brief` print the exact prompt the subagent must be given, so the tool writes the brief, not the worker.
- OC1 can become a Checked criterion. The dispatcher already reads the CLI's stream-json, so it can flag a review whose session's tool calls named a path outside the view. Pin it with a fake CLI that emits such a `tool_use`.

### F6 [high] A second off-course verdict never blocks a ticket that went back to z-design
Where: c0262.md:85 (`blocked`), :87 (`reviews` reads "the `final-review-NNN.md` files committed on the layer"), :93 (the `redesign` route); proto `finalread.luau:132`.
Evidence: `where` takes the newest raft's layer, and `reviews` reads only that layer's tip. The `redesign` route is `./zn stop`, `./zn unfold`, re-prep, z-raft, z-ready. The off-course `final-review-001.md` stays on the old layer branch (z-stop leaves branches as they are) and never reaches main. So the re-prepped ticket's new layer has no reviews. Its next off-course verdict reads as the first (`redo-design` again), and the loop never reaches `blocked`.

The redesigner is told to "read that review's gaps first", with nowhere to read them from. verdict.spec's blocked cases are pure lists, and fixture.spec reaches `blocked` only on the rebuild route.
Critique: the captured rule "A second off-course verdict blocks the ticket" holds on one route only.
Consequences: carrying the reviews forward means a tracker write during the stop, numbering that continues (the new layer's first review must be 002), and the re-prep reading the reviews as its input. That is fine: they are trail for design mode, and the next final review still sees only its view.
Recommendation:
- Before `./zn stop`, the `redesign` step publishes the layer's `final-review-NNN.md` files into the issue folder on origin/main. Alternatively, `./zn stop` and `./zn unfold` carry them as tracker files of the issue.
- `finalread.reviews` reads, by number, both the issue folder on origin/main and the one at the layer tip. The dispatcher numbers after both.
- z-design's re-prep reads them first.
- Add a fixture.spec case: an off-course review with a design gap, then the route, then a new raft and layer. `./zn final` shows the earlier review, and an off-course review there is `blocked`.
- Add the mutant "reviews from the newest layer only".
Lesson: z-design/results-land-on-every-path

### F7 [high] A blocked or redone ticket keeps the green layers below it from landing
Where: c0262.md:91 (`done` refuses "a member whose state is …"), :93 (`blocked` and `redesign` both go to `./zn stop`); proto `main.luau:5046` (`for _, m in store.members(raft.id)`).
Evidence: c0248's Q3, confirmed by the user, says: "A red or blocked layer stops the layers above it, not the ones below. The green layers below a blocked one land now." c0248 builds that as `./zn done <R> --through <issue>`, with `ZN_BIND_MEMBERS`. c0262's refusal loops over every member, so a blocked layer above refuses `done --through` for the layers below it, which is the one case `--through` exists for. The worker's `blocked` and `redesign` actions also go straight to `./zn stop`, which gives the on-course layers below back unlanded.
Critique: this contradicts a user decision this design relies on (c0248 is a dependency). It also throws away completed, on-course layers.
Consequences: the refusal and the route both need c0248's landing set, and for unmarked rafts (no `--through`) today's stop stays.
Recommendation:
- Limit `done`'s refusal to the members being landed (`ZN_BIND_MEMBERS`, or the `--through` set).
- In `work.luau`, for a marked raft whose layer below is on course, make `blocked` and `redesign` say `./zn done <R> --through <the issue below>` first, then `questions.md` and `./zn stop` (plus `unfold` for a redesign). c0248 already makes `stop` leave landed members in `done/`.
- Add a fixture case: two layers, layer 1 on course, layer 2 blocked; `./zn done R0010 --through c0010` lands layer 1. It stays red until c0248 is done, like AC13.
- Add a work.spec case: blocked on layer 2 with layer 1 on course names `--through c0010`.

### F8 [medium] `design.md` carries the review trail on real tickets
Where: c0262.md:81; view.spec AC1 (its `CURRENT` Design is free of trail).
Evidence: Design sections cite reviews and refutes. c0260's Design opens: "**STATUS: prepared. design-review-008 (round 6, the final round) has no high finding and every finding is answered `fixed` in design-refute-009.md…**", and later cites "design-review-004 F7". Of the prepared Design sections, 15 lines in c0189's, 12 in f0143's and 8 in c0123's mention a design review or a refute. The view shows all of them, against the captured "no design reviews, refutes".
Critique: the limit holds only for documents that already keep reviews out of the Design, and the spec's fixture is one of them.
Consequences: stripping lines could remove real design content, so the rule has to keep new Designs clean in the first place.
Recommendation:
- Add a z-design rule that the Design and Acceptance criteria sections name no review, refute or round; that record lives in Unknowns & experiments and `harvest.md`.
- Have `finalview.design` drop every line that matches `design-review-%d`, `refute-%d`, `review %d%d%d F%d` or `round %d`, and add a README line saying such lines were removed.
- Add a view.spec case with a STATUS line citing design-review-008.

### F9 [medium] The last review runs before the layer's code review
Where: c0262.md:93, :226 (step 3: "If c0248 has landed a per-layer code review in `work.luau`").
Evidence: c0248's Touched modules include neither `work.luau` nor `workread.luau`, so by c0248's own design that condition is false. c0262's `finalStep` then fires as soon as the layer is `finished`, before the per-layer code review that c0248 requires for completion. The user calls the full-force review the last one ("reviews are back and forth EXCEPT for the last one"), and the 2026-11-11 order is "built, reviewed, full-force reviewed". Each code-review fix then changes the view, so every layer pays one more xhigh run. One off-course verdict before the fixes and one after is `blocked`.
Critique: the order is left to a condition c0248's design already settles.
Consequences: the worker has to learn the layer's code-review state, which work next cannot read today.
Recommendation:
- `LayerFact` gains the layer's completion reason without `final` (c0248's `completion.layer`; nil when complete). workread reads it for marked rafts.
- `forRaft` says to run the layer's code review (dispatched with the issue id, c0248 outcome 8) while that reason is set, and says `final-review-ticket` only after.
- Add a work.spec case: a finished layer whose code review is unsettled gets the code-review action, not `final-review-ticket`.
- Remove the condition from step 3.
Lesson: z-design/quote-other-preps-before-promising

### F10 [medium] Two ways round the redo
Where: c0262.md:85, :91.
Evidence:
1. For an unmarked raft, `done` refuses only the redo states, `blocked` and `invalid`. After an off-course verdict, any commit (one changed byte) makes the state `review-again`, and `done` then lands a ticket judged off course whose redo was never reviewed. fixture.spec reaches exactly that state at line 224 and never runs `done` there.
2. `state` reads only the latest review. An `off-course` review of view v1 followed by an `on-course` review of the same v1 reads as `on-course`. The dispatcher refuses that second run, but the interactive path and a file committed by hand do not.
Critique: the captured "then the review runs again" can be skipped on either path.
Consequences: refusing `review-again` must not refuse a ticket that has no review at all; that stays unrefused, per the user's (a).
Recommendation:
- In `state`, a review of a view that an earlier off-course review already judged is `invalid` ("reviewed again without a redo").
- `done` also refuses `review-again` when the latest verdict is off course. A ticket with no review stays unrefused.
- Add verdict.spec cases for both.
- Add a fixture.spec assertion: `done` after the rebuild still refuses.

### F11 [medium] fixture.spec's later `work next` assertions pass for the wrong reason
Where: `acceptance/fixture.spec.luau:223-241`; c0262.md:89 ("on today's main any tracker file of the ticket is accepted").
Evidence: today's `layergit.isPostFinishPath` (`layergit.luau:118-141`) accepts only three things: `spend.d`, the raft folder's files, and the issue document `<id>/<id>.md`. It does not accept `final-review-001.md` in the issue folder. So on the prototype, the "final review 1" commit already un-finishes the layer, and the "rebuilt" commit certainly does, since it touches `pickman/src` after the finish commit.

From then on, `work next` prints the `finish` action. Its text contains "blocked" ("The same check failing after a real second attempt is blocked: write questions.md…") and does not contain "final-review-ticket". So lines 234 and 241 still hold with c0262's work wiring deleted. The real redo flow is never run on git: rebuild, `./zn finish` again (squashing the committed review into the finish commit), `review-again`, a new review, `on-course`, then the next action.
Critique: the spec does not test what its case name claims, and the design rests on a false statement about today's main.
Consequences: once the flow is run, the spec also shows whether a committed review survives the re-finish.
Recommendation:
- After the rebuild, run `./zn finish c0010`.
- Assert the exact action in `work.say`'s form (`": final-review-ticket c0010 - "`, `": blocked c0010 - "`), and the next action word after `on-course`.
- Assert that `./zn final` still reads review 001 after the re-finish.
- Correct the sentence about today's main: c0248 widens the list, and c0262 adds `final-review-NNN.md`.

### F12 [medium] The reader does not enforce what the captured verdict needs, and an unreadable review blocks with no retry
Where: c0262.md:84; proto `finalview.luau:239`; the dispatcher's landing.
Evidence:
- The capture asks for "each gap named against the ask or the design", but `problem` never checks the `Measured against:` line, so a finding without one is accepted.
- The pattern `\nGap:%s*(%a+)` reads the README's template line `Gap: design | implementation` as `design`, which sends the ticket back to z-design.
- The dispatcher lands `review.md` unchecked. A model that ends with `Verdict: approve` (zz-review's usual shape) or leaves out the View line makes the ticket `invalid`, and so blocked for the human, after a single run.
Critique: the parser accepts findings the capture's verdict needs and rejects the model's habit only after it lands.
Consequences: a rejected review is never placed, so the one-round rule does not count it.
Recommendation:
- `problem` requires each finding to have a non-empty `Measured against: "<quote>"`. Optionally, when the review's View is the current one, the quote must occur in `ask.md` or `design.md`.
- The Gap line must be exactly one word.
- The dispatcher runs `parse` and `problem` on `review.md` before numbering it. A problem is a failed try: the file is not placed, and either the next try runs or the step fails naming the reason. `invalid` then only comes from a hand-committed file.
- Add verdict.spec cases: no `Measured against`; the template Gap line.
- Add a dispatch.spec case: a fake CLI that writes `Verdict: approve` leaves no `final-review-001.md`, and the step fails naming the problem.

### F13 [medium] An off-course ticket review is a harvest stem that nobody harvests
Where: c0262.md:93, :97; `lessons.luau:152-155` (`final-review-NNN` is a stem), :134 (`### F<n>`).
Evidence: `./zn lessons --uncovered <issue>` lists each `### F<n>` of an issue folder's `final-review-NNN.md`. The dispatcher reads that list after every step that ends ok (`dispatcher.luau:1657`), and zz-execute Phase 5 step 4 requires `--uncovered` to pass. No step (`rebuild`, `redesign`, zz-execute 4a) says who harvests these findings, and the ticket review has no author round in which to do it.
Critique: every off-course verdict leaves findings that the existing harvest checks will flag, with no step that clears them.
Consequences: harvested final-review findings become lessons, which the next final reviewer must not read. Its view already keeps it out of lessons once F5 is fixed.
Recommendation: choose one of these and say which.
- The `rebuild` and `redesign` texts and zz-execute 4a tell the worker to harvest each finding into the issue's `harvest.md` (a lesson or `one-off:`) before it re-finishes or stops. work.spec asserts the words.
- Or, if these findings are not meant to become lessons, `lessons.isStem` excludes final-review files in an issue folder.

### F14 [low] The prompt still sends the final reviewer out of its folder
Where: proto `dispatch.luau` prompt lines (final mode with `viewDir`).
Evidence: the generic line remains: "write `## Open to the human` in the item's document, one bullet per finding … and stop". The item's document is outside the view, and the last review has no refutation round.
Critique: the prompt says "read only the files in this folder" and then sends the reviewer to edit a file outside it.
Consequences: none.
Recommendation: in final mode on a ticket, drop that line, since the off-course verdict is the output. Pin it with a dispatch.spec assertion that the log does not contain "Open to the human".

### F15 [low] `keepPath` hides other items' documents that a ticket delivers
Where: c0262.md:79.
Evidence: `keepPath` drops every path under `.tracker/issues/` and `.tracker/rafts/`. Some tickets deliver an edit to another item: a `Scope decision` line landed on the acting item's Problem (rulings-reach-every-acting-item), or an emergent issue the work files. For those, the reviewer sees no delivery and reads the ticket as off course.
Critique: the filter removes deliverables along with this ticket's bookkeeping.
Consequences: none.
Recommendation: drop only this ticket's folder, this raft's folder and `spend.d/` anywhere; keep other items' documents. Add a view.spec case.

### F16 [low] The dependency chain is not named, and the in-flight analysis describes a raft that does not exist
Where: c0262.md:70, :106.
Evidence: c0248 is done only when its layer lands. That happens in R-vision's single bind (c0248 Q4 and Q8) or through a `--through` landing. So c0262 can be readied only after R-vision (c0248 to c0254) and R-vision's outside dependencies (c0257, c0260, c0261, c0263, c0283 and the heartbeat raft), and the design never names that chain. R-vision is not a raft today (c0248's `raft:` is empty), so the case "Active raft R-vision members … have finished layers with no ticket review" when c0262 lands cannot happen.
Critique: the user is not told how long c0262 waits, and the migration paragraph analyses the wrong rafts.
Consequences: none.
Recommendation: name the chain under Dependencies and put the order to the user as a guess. Rewrite the Chore checklist's in-flight paragraph for the rafts that will actually be in flight when c0262 lands: those readied after c0248 lands (see F2).
Lesson: z-design/depends-on-inherits-the-dependency-raft

### F17 [low] AC2's contract clause has no case
Where: view.spec AC2; check.sh AC2 line.
Evidence: the check names "the design, the contract and the diff", but the spec changes only the diff and the design. A `viewId` that skips `contract/` passes.
Critique: one clause of a Checked criterion has no test that can fail.
Consequences: none.
Recommendation: add a case that changes `contract["check.sh"]`, and a mutant row "leave `contract/` out of the id".

## Checked and clean
- **Scope fidelity:** the capture is confirmed (0e91b4d7). The title, Problem and Solution have gained only decision lines. Every captured outcome has a Design and a Checked criterion. The reading of "design covers the idea" is escalated properly as O1, quoting the user's 2026-11-13 words. F4 and F6 are where the delivered behaviour falls short of an outcome.
- **Repository safety:** fixture.spec and dispatch.spec build their own repositories under `.cache/final-*-github.com`, with fake `gh` and `claude`. docs.spec only reads. The other specs are pure.
- **Bounded commands:** the experiments were specs and the gate. The real-model run the design leaves to the executor should go through `./zn run --time` (part of F5's E7).
- **Lessons:** `harvest.md` holds one valid note; F3 is where the lesson it names is not applied.

## Lesson candidates (for the lead)
- A reviewer whose inputs must be limited starts outside every directory that has agent-instruction files. The CLI loads `CLAUDE.md` and `AGENTS.md` from the working directory's parents before any prompt is read. Check: does any limited-view reviewer start in a folder with a `CLAUDE.md` or `AGENTS.md` above it, and what did a real run of each runtime load?
- A reader of user decisions covers every place the repo writes them. Decisions appear as Problem lines, bullets, `Ruled (user, …)` bullets under Open to the human, other sections and post-capture confirmation. Check: list each place a ruling is recorded, and give one spec case per place.

Verdict: changes

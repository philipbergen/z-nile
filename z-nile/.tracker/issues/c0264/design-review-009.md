# Review 009: c0264 (design mode)
Inputs: prep worktree at a0d25595 with the uncommitted c0264.md, check.sh and experiments/readme.patch (`git diff` of the three read in full), acceptance/intent-ac1..3.spec.luau, roadmap-unique.spec.luau, harvest.md, design-review-005..008 and design-refute-005..008. origin/main is 2c20b9da. origin/capture-workers is 2e282833, and it is still not an ancestor of origin/main. Captures read from that branch: c0264 and c0261. The c0264 capture, compared with this document's Problem: equal, plus the option (b) lines and the new c0261 `Decided with the user` line.
Prototype: `.cache/rev9-c0264`, a clone of the worktree. I copied the issue folder in, applied readme.patch, and copied c0263.md and c0265.md from origin/capture-workers. No commit and no git identity. It ran through `./zn run --time 300`. `./zn check c0264`: 11/11. The clone was removed afterwards.
Round 5 of the restarted count. The answers to 008 still hold:
- F1: "that names the same ticket" is in the Intent, AC4 and the patch, and conflict (5) lists c0254 and c0251.
- F2: AC7 keys on a title word.
- F3: harvest maps 006 F2 to exact-checks-compare-against-the-merge-base.
- The prerequisite (capture-workers unlanded, f0263 and f0265 still on main under f ids) is still the user's to settle, and it is escalated. I don't repeat it.
This round's focus is the c0261 decision. Outside the Intent lead-in and the worker's "cheap model", no tier vocabulary is left in the pinned README text. `grep -niE 'tier|sharp|cheap|wait'` over the patch, check.sh and specs found only the lead-in "Cheap on the way, sharp at the end", "a cheap model", "a cheap supervisor" and "named level". All of these are prose, not a mechanism. What is wrong is what the rewording took out alongside the tier names.

### F1 [high] The rewording dropped "the cheapest when waiting", a captured outcome that the decision does not touch
Where:
- Intent bullet 3 (Design block, AC4 heredoc, patch line 13): "Expensive models run every final review; cheaper, faster models do the work on the way there and the waiting."
- Models per command and activity: "Cheaper, faster models do the work on the way there and the waiting."
- the c0261 diagram line, which lost "cheapest waiting".
- Source map: "cheaper and faster on the way and when waiting".
Evidence: three texts ask for a third, lowest-cost class for waiting:
- c0264's capture (Problem, Intent bullet): "Cost stays low: sharp, expensive models for every final review, cheap and fast ones on the way there, **the cheapest when waiting**."
- The ask quoted in this issue: "Use cheap haiku or composer models or similar when waiting for things".
- c0261's capture: "A long wait or poll runs on the wait tier".

The previous text kept that class ("and the cheapest wait", "the cheapest for waiting"). The new text puts waiting in the same class as the work on the way.

The user's decision is about naming: "I don't want weird names for each model, I want real model names assigned to tasks … just tie the models to each command and activity". Waiting is an activity, and giving it the cheapest real model is exactly a model tied to an activity. Nothing in the quote removes the outcome. The words "(no cheap/sharp/wait as a mechanism)" are the author's gloss, appended to the Decided line; the user did not say them. So a captured outcome is reworded away with no Scope decision behind it (zz-review item 11).
Critique: the tempting fix is to bring back "the wait tier" or "the cheapest tier". That reintroduces a named level, which the user just rejected.
Consequences: the restored words must describe a cost, not name a level. Four places carry this text and change together: AC4's INTENT heredoc, AC5's SECTIONS heredoc, the Design blocks and the patch. The diagram line is optional: AC8 names c0261 either way. The Source map line should then say "the cheapest when waiting" too.
Recommendation: in the Intent, write "Expensive models run every final review; cheaper, faster models do the work on the way there, and the cheapest do the waiting." In the sub-section, write "Cheaper, faster models do the work on the way there, and the cheapest models do the waiting and polling." Strike the gloss in parentheses from the Problem's Decided line, or move it into the Design as the author's reading. Add a Rules and mutants row for "waiting folded into the way there" (it fails AC4 and AC5), and run it.
Lesson: z-design/never-narrow-captured-scope

### F2 [medium] The c0261 example reads the user's example one way and so decides a conflict between two of the user's statements. The real models the ask names are gone
Where: Models per command and activity: "z-ticket's sharpening of the idea and its review, for example, use different models (such as sonnet-5.5-high and grok-4.7-high). Expensive models run every final review: the idea review, …"; the Design's Source map and conflict list
Evidence:
- The user wrote `z-ticket-sharpen:sonnet-5.5-high, grok-4.7-high`. As written, that is one activity's key with two models after it, which is most naturally one model per CLI. The README instead pairs them as sharpening → sonnet-5.5-high and review → grok-4.7-high.
- That pairing puts the idea review on grok-4.7-high. The very next sentence says the idea review is a final review on an expensive model. The ask quoted in this issue says "agent and grok are 4.6 high for cheap 4.7 xhigh for expensive". Read the README's way, the decision's example names a different expensive grok model from the one in the ask. That is a conflict between two statements by the user, and the README settles it silently, in pinned text.
- The sentence also says "a real model per CLI", yet its example takes the two activities' models from two different CLIs.
- The provider guidance in the ask was in the previous sub-section and is now absent: 4.6 at high on the way, 4.7 at xhigh for final reviews, haiku or composer when waiting. These are real model names, which is what the decision asks for, not tier names.
Critique: the tempting fix is to restore "sharp is 4.7 at xhigh". That decides the conflict the other way.
Consequences: whatever the README names as a model for an activity becomes a claim that c0261's own design must either honour or reword. So the README should name only what the user has said without contradiction, and list the rest as a conflict.
Recommendation:
- Make the example neutral: "z-ticket's sharpening of the idea and its review, for example, each have a model of their own".
- Add conflict (6), decided by no one here: the ask's "4.7 xhigh for expensive" against the decision example's "grok-4.7-high". Also name which activity each model in that example is for.
- Escalate to the user whether the README keeps the ask's provider guidance, and in what form. One option is attributing it: "the ask's guide: grok and agent 4.6 at high on the way, 4.7 at xhigh for every final review; haiku or composer when waiting". Keeping it costs one pinned sentence plus the conflict entry. Dropping it is a cut, and only the user can make it.
- Update AC5's heredoc, the Design block and the patch together.

### F3 [medium] "Models per command and activity" labels as captured what already exists. A real model per command and CLI is c0117's `.models.toml`, and spend already records the model
Where: Models per command and activity: "Each command and activity is assigned a real model per CLI … Spend records the model. *captured* (c0261)"
Evidence:
- c0117 is done (`./zn find c0117` gives `z-nile/.tracker/issues/done/c0117`).
- `.models.toml` already has `[z-ticket.claude] model = "claude-sonnet-5"` and `[z-ticket.grok] model = "grok-4.7"`, so a real model per command and CLI exists today.
- spend.md already has a `model` column (this issue's rows read `claude-opus-5-5`).
- README line 115 already says the dispatcher "records each step's tokens and model on its spend row".
- c0261's capture describes the new part itself: "Today `.models.toml` names one model per skill and CLI".
After the decision, what is new is a model per *activity* within a command (sharpening against review), and the cost per activity showing up in spend. That last part is the analogue of "so the cost per tier shows", which was also dropped. As written, a reader cannot tell which parts are built, and two of the three statements describe built things labelled *captured*.
Critique: this breaks the README's label contract in the opposite direction from JC2: built behaviour is labelled not built. The tempting fix is to delete "Spend records the model". That loses c0261's spend outcome instead of translating it.
Consequences: an *exists* (c0117) label in the sub-section is read from the tracker by AC6, which says exists, so it passes. The Roadmap row 95, "c0117 | designed", is already stale, but it is an existing line that JC1 keeps; the review report should pass it to c0117's or c0259's owner, not change it here.
Recommendation: reword the sub-section along these lines: "Today `.models.toml` names a real model per command and CLI *exists* (c0117). Each activity within a command gets its own real model too: z-ticket's sharpening of the idea and its review, for example …; spend records the activity beside the model, so the cost of each one shows. *captured* (c0261)". Update AC5's heredoc, the Design block, the Source map and the patch. Add a mutant: the c0117 label changed to *captured* fails AC6. Run it.
Lesson: z-design/status-labels-need-a-tracker-fact

### F4 [low] The body still points at the removed Model tiers text, and this round's change has no record
Where: Rules and mutants row for AC5 ("`[tiers.<cli>]` added to Model tiers (M7)"); conflict (1) ("the user has decided against that (below)"); Unknowns E4 ("the seven added lines"); Unknowns & experiments
Evidence:
- M7 names a section that no longer exists, and it was run against the old text.
- The c0261 decision sits above conflict (1), in the Problem and the paragraph before, not below it.
- The diagram adds eight lines.
- No line in Unknowns records that this round reran `./zn check` (I got 11/11) or the mermaid parse after the c0261 diagram label changed.
- AC7's c0261 key word is "model", so the old tier row `| model tiers: cheap, sharp, wait | c0261 | captured |` passes. I ran it: `PASS AC7`, 11/11. This is deliberate, since siblings may word their rows. But the Design's "The README names no tiers" holds only for the pinned blocks, and the Design doesn't say so.
Critique: these are stale pointers left by a decision. None of them changes the README.
Consequences: none.
Recommendation:
- Rename M7 to "a tier table added to Models per command and activity" and rerun it.
- Fix "(below)" and "seven".
- Add an Unknowns line for this round: the c0261 decision, the rerun (11/11), and E4 rerun or marked not rerun.
- Say in Siblings that row wording is not held to the no-tier decision.
Lesson: z-design/decided-guesses-rewrite-their-body

Candidate lesson (for the lead to harvest): when a user decision replaces a mechanism's vocabulary (named tiers → real models per activity), rewrite only the vocabulary and translate each outcome the old text carried, such as the cheapest class for waiting or the cost per class in spend. Don't drop an outcome along with its name. Check: for each outcome the old text stated, where does the new text state it, and does a gloss attached to the user's quote add anything the user did not say?

Verdict: changes

# Review 006: c0264 (design mode)
Inputs: prep worktree at 81dded29 (origin/main 22665847 has changed no README, spec, lib or engine file since that merge), with the uncommitted c0264.md, check.sh, experiments/readme.patch, harvest.md, design-review-005.md and design-refute-005.md; acceptance/intent-ac1..3.spec.luau. Capture: `git show origin/capture-workers:z-nile/.tracker/issues/c0264/c0264.md` (2e282833, still not on main). `./zn capture c0264` still prints the old one-line capture (c8c78404). The captures of c0175, c0248, c0249, c0250, c0253, c0257, c0260, c0261, c0262, c0263 and c0265 were read from origin/capture-workers. Prototype: `.cache/rev6-c0264`, a clone of the worktree with the issue folder copied in, readme.patch applied, and c0263.md and c0265.md copied from origin/capture-workers. `./zn check c0264` gives 10/10. Every heredoc line of check.sh (`*STATE*` read as `*captured*`) is found with `grep -xF` in c0264.md and as a `+` line of readme.patch.
Round 2 of the restarted count. Dropped from design-review-005: F1 (the c0263 diagram line and AC8's id check are there), F3 (the "only for a block" sentence is gone, the step list is "ready, run, review, gate, merge", conflict (4) is listed), F6 (the three wordings and the c0261 label are fixed), F7 (loose ends outside c0264's text; the f0263 vacuity and follow-ups are the coordinator's). Two findings repeat as F3 and F4. F5 questions the mechanism behind 005 F4.

Scope fidelity: the Problem equals the capture plus one `Scope decision (user, 2026-11-07)` line and one `Decided with the user (2026-11-07)` line. The title gains only spelling. The Solution is unchanged. Each captured outcome has a Design text and a Checked criterion. The three known conflicts are each stated as the capture states them, and none is decided: the README names no `[tiers.<cli>]` table and no `./zn approve`, and it does not say a person comes back only for a block.

### F1 [high] AC5 and AC7 pass when the nine sub-sections are outside "How it should work" and the rows are outside the Roadmap
Where: check.sh `section()`, `verbatim_sections`, `labels_in_sections` and `roadmap_rows`; AC5's label ("each new sub-section of How it should work"); Design "Where" ("The nine sub-sections go in `## How it should work` just before `### Roadmap`")
Evidence: in `.cache/rev6-c0264` I made two mutants.
- Mutant A moved the nine sub-sections, unchanged, to the end of the README, under `## Where the work lives`. `grep -n '^##'` puts them at lines 214 to 238, after `## Where the work lives` at line 203. `./zn check c0264` gives `PASS AC5 … PASS AC6 … PASS AC10`, 10/10.
- Mutant B moved the seven rows out of `### Roadmap` into a new table at the end of the file (`| later | id | state |`). The result is `PASS AC7`, 10/10.

`section()` finds a `### <title>` anywhere in the file. `roadmap_rows` greps the whole file. c0259's promoted spec checks labels only inside the workflow section, so it cannot see sub-sections that are not there.
Critique: the capture's outcome is that "'How it should work' describes" each mechanism, and that "the roadmap table … gain[s] the new tickets". Both criteria can be passed by an implementation that does neither, and AC5's label claims a placement its command does not check (spec-design-correspondence). The tempting fix is to require the nine sub-sections to be contiguous and directly above `### Roadmap`. That fails a correct c0264 as soon as a sibling (c0260, c0261 or f0265, all editing this README) adds its own `###` sub-section in between.
Consequences: a placement rule must survive siblings' additions. Order and section membership survive them. Contiguity does not.
Recommendation:
- Scope `section()` for the README to the body of `## How it should work`, up to the next `## `, the way c0259's `workflow()` does.
- Make AC5 also require that the nine titles each appear exactly once as a `###` of that section, in the Design's order, all before `### Roadmap`. Don't require them to be adjacent.
- Scope `roadmap_rows` to the `### Roadmap` table, between `### Roadmap` and the next `### `, as c0259's AC3 reads it.
- Add mutants A and B; each must fail.
- Add a correct variant that must pass: a sibling's own labelled `###` inserted between "Model tiers" and "The full-force final review".
- Relabel AC5 and AC7 so each label says what is now checked.
Lesson: z-design/spec-design-correspondence

### F2 [medium] AC7 no longer holds the row text that the Design says is held word for word
Where: Design paragraph 1 ("the texts below are the required texts, held word for word by `check.sh`"), "Roadmap rows"; check.sh `roadmap_rows` (`ROWS` is read only for its ids)
Evidence: `roadmap_rows` counts `^\| .* \| $id \| (exists|designed|captured) \|$` and compares the state. The piece text is never compared. So `| x | c0261 | captured |` passes AC7, and so does any other text. Round 1's fix for 005 F2 traded the text pin for tolerance of a sibling's row.
Critique: an executor who rewords or drops the description of the seven pieces passes. The Design's claim that every block is held word for word is now false for one block. There are two tempting fixes. Pinning the text again fails a correct c0264 when c0260 lands first with its own row. Deleting the "word for word" claim leaves the rows unchecked.
Consequences: a check that is both tolerant and exact must know which rows were already there before this change. That means reading the merge base, not a frozen tree.
Recommendation: an id that has no Roadmap row at `git merge-base HEAD origin/main` must have exactly the Design's row, with its state read from the tracker. An id that already had one there keeps that row, with any text, and only its state is checked. Exactly one row per id holds either way.
Spec cases:
- c0260's prototype row (`| capture interview and idea review (`capture/`, `zz-review --mode idea`) | c0260 | exists |`) on the base passes.
- The same row added on the branch instead of the Design's row fails.
- A reworded c0261 row fails.

Record the mutant in Rules and mutants.
Lesson: z-design/exact-checks-compare-against-the-merge-base

### F3 [medium] (repeat of design-review-005 F2) The promise that a sibling "edits the existing row instead of appending one" is in no sibling's documents, and nothing after `done` enforces it
Where: Design "Siblings" ("if c0264 lands first, the other PR edits the existing row instead of appending one (the report tells their leads)"); design-refute-005 F2
Evidence:
- `grep -n c0264` over `.worktree/prep-capture-interview-and-idea-review/…/c0260/c0260.md` finds no such rule. Its `experiments/prototype.patch` still appends `+| capture interview and idea review … | c0260 | exists |`. Its `skills-restated.spec.luau:54` accepts any c0260 row, so a second c0260 row passes it.
- A second sibling has turned up since round 1. `.worktree/prep-work-heartbeat/…/f0265/check.sh:25` requires `grep -qE "^\| .* \| f0265 \| exists \|"`, which is a row of its own for the same heartbeat work that c0264 lists as `| work heartbeat, lost items first | c0265 | … |`.
- c0264's AC7 is sequestered and is not run once c0264 is done. AC1 to AC3, the promoted specs, say nothing about rows.

So if c0264 lands first, a duplicate row lands green.
Critique: round 1 found this hole, and the answer moved it into a report. A promise to another prep that is not in that prep's documents is the lesson's defect. Round 2 finds it again, so the mechanism is what fails: a promise depends on every sibling's lead remembering it.
Consequences: a rule enforced by the gate needs no promise. It holds whichever PR lands second. The second PR's own gate turns red, and the fix is the edit that the Design asks for.
Recommendation: promote a rule-level case, in a new `acceptance/intent-ac4.spec.luau` or as a case of AC1's file. It is a rule over every row, not today's set (promoted-specs-pin-rules-not-sets): "no issue id has more than one row in `### Roadmap`". Today's 11 rows are distinct, so it is green on main and on the prototype. Mutant: the prototype plus c0260's appended row must fail. Then rewrite "Siblings" to say the gate holds the rule, and name c0260 (its prototype row) and f0265 (its check.sh line 25) with the quoted lines. Keep "the report tells their leads" only as a courtesy.
Lesson: z-design/quote-other-preps-before-promising

### F4 [medium] (repeat of design-review-005 F5) The prerequisite is still undecided and unrecorded. Step 1 checks only two ids, not the captures the README restates
Where: Design "Prerequisite (a hard stop)"; Implementation step 1; design-refute-005 F5 ("escalated in the report")
Evidence:
- origin/capture-workers (2e282833) is still not an ancestor of origin/main (`git merge-base --is-ancestor` fails), and main is now 47 commits past its base.
- f0263 and f0265 continue under their f ids. f0265 is at review round 3 (`prep-work-heartbeat`, untracked `design-review-003.md`), and its check.sh requires an `f0265 | exists` row (F3).
- c0260, c0261 and c0262 exist on main with older captures (`git diff --quiet origin/main origin/capture-workers -- …/c0260/c0260.md` reports differs, and the same for c0261 and c0262). The README's texts follow the capture-workers versions.
- Step 1 stops only on `./zn find c0263 && ./zn find c0265`. A coordinator who lands c0263 and c0265 by renaming the f preps, without the capture rewrites, passes step 1. The README then restates c0260's, c0261's and c0262's captures as main does not have them, labelled `*captured*`.

No `Decided with the user` line records how the rename is settled.
(Aside: the refute says `real` returns "missing" for an f id. `labels_true` only ever matches `c` ids, so it never calls `real` with one. A label on `f0263` fails through AC5's `norm` instead. I ran it: `FAIL AC5 … *captured* (f0263)`, `PASS AC6`. The outcome is the same: it fails closed.)
Critique: an issue set to `design: ready` whose first step depends on a coordinator's choice that nothing records is not executable from the documents. z-design step 5 sends anything unsettled to the user before `design: ready`. The tempting fix is a longer stop list, which still leaves the choice open.
Consequences: if the f ids stay, the four labels, two rows and two diagram lines naming c0263 and c0265 change, and so does F3's duplicate rule.
Recommendation: escalate to the user, or the coordinator, before `design: ready`. The options are:
- (a) land capture-workers, renaming the f0263 and f0265 preps;
- (b) keep the f ids and rewrite c0264's texts to name them.

Record the answer as a `Decided with the user` line. Extend step 1's stop to the rewritten captures as well: for each of c0253, c0260, c0261 and c0262, a marker sentence of the capture-workers Problem must be on origin/main (for example `**A raft, not a step.**`, `**Idea review.**`, `Each CLI has three tiers`, `**Limited view:**`). Otherwise post BLOCKED.
Lesson: z-design/quote-other-preps-before-promising

### F5 [medium] The Intent's reading rule needs "older" and "newer", which the README never marks. A reader cannot apply it
Where: the Intent's last paragraph ("where an older line below and a newer sub-section of the same ticket differ, the newer one follows the ticket's current capture"); design-refute-005 F4
Evidence: with the patch applied, `## How it should work` holds `### Order` (c0249, "every issue and raft gets a `rank:`") and `### Rank and lost work` (c0249, "may carry a rank, and unset is the lowest"). It also holds `### Two ends, one stack` (c0253, "takes the next item from the stack") and `### The worker, z-work` (c0253, "It picks up a raft"). Nothing in the README dates either side, and the order of sections is not chronological: the older `### Stacked delivery` sits after the new sub-sections and the Roadmap. Round 1's Recommendation named the set ("a sub-section added for the 2026-11-07 ask"). The adopted wording dropped that anchor.
Critique: this rule is the mechanism that the last three rounds settled on for every contradiction between old and new lines (004 F1 and F3, 005 F4). As written, it resolves nothing for a reader, who sees two c0249 rules and cannot tell which wins. The tempting fix is to date each sub-section. That adds a new kind of label that c0259's vocabulary rule does not know.
Consequences: naming the set by its titles fixes it for good. A later ticket's sub-section is not in the named set, so it never silently inherits precedence. The follow-up that removes the rule (already in the Decided paragraph's list) removes the names with it.
Recommendation: write "where a line below differs from one of the sub-sections The worker, z-work to The board app (added for the 2026-11-07 ask) that names the same ticket, that sub-section follows the ticket's current capture". Keep the second clause about designs drafted by a worker. Update AC4's text, the Design block and the patch together. Add a mutant in which the rule is put back without the anchor, and AC4 must fail.
Lesson: z-design/restated-rules-move-together

### F6 [low] Provenance, Rank and lost work leave out parts of their captures, and conflict (4) cites text the patch does not have
Where: sub-sections Provenance and Rank and lost work; Source map; Design conflict (4) ("the same patch's rank asks …, the board's drag and drop and rank provenance")
Evidence:
- c0263's capture lists "who confirmed the idea (c0260), who set the rank, who rafted it, and which worker … delivered each layer" and says "The board shows them". The README's Provenance has neither the idea confirmer, the rank setter nor the board.
- The Source map says c0249 includes "`./zn rank` unsets", but the Rank sub-section does not say it.
- c0265's "the takeover is recorded (c0263)" and "the next worker resumes it" are missing.
- Conflict (4) names "rank provenance" as part of "the same patch", and the patch has none.

Critique: none of this contradicts a capture, but the source map claims statements the README does not make. Dropping "who set the rank" while conflict (4) still cites it reads as if the text was trimmed to avoid the tension. Restating the capture, labelled captured, decides nothing.
Consequences: AC5's texts change. AC6's labels do not.
Recommendation:
- Add "who confirmed the idea, who set the rank" and "The board shows them" to Provenance.
- Add "`./zn rank` can also unset a rank" to Rank and lost work.
- Add "a worker that takes over lost work claims it as usual, and the takeover is recorded" there too, labelled c0265.
- Or, if any of these is left out on purpose, correct the Source map and conflict (4) so they say only what the patch says.

### F7 [low] The frontmatter says `prepared` while the design is `reviewed`
Where: c0264.md frontmatter (`design: reviewed`, `status: prepared-heron-jolly-plucky`)
Evidence: `./zn status c0264` prints `preparing` (origin/main). The local `prepared` stamp is left over from round 4's prep commit (fa3e699f), before the scope was rewritten. zz-rules says "`design: ready` is prepared".
Critique: a prep PR merged in this state would show an item as prepared whose design is not ready.
Consequences: none beyond the stamp.
Recommendation: put the stamp back to the `preparing` value origin/main has, and run `./zn status c0264 prepared` only after `design: ready` (z-design step 5).

Candidate lesson (for the lead to harvest): a check that a document gained a section or a row also checks where it is, by its parent heading or table, never by grep over the whole file, because c0264's AC5 and AC7 passed with the sub-sections under another `##` and the rows in another table. Check: does each "the document has X" check fail when X is moved, unchanged, to another section of the same file?

Verdict: changes

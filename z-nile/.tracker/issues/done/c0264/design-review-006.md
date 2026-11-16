# Review 006: c0264 (design mode)
Inputs: prep worktree HEAD a6090d58a4cd0a584ba4c501657cc3179d87f8a3 (tracker: prep c0264 answer design-review-005); c0264.md, check.sh, diagram.txt, legend.txt, acceptance/intent.spec.luau, acceptance/roadmap-unique.spec.luau, experiments/README.draft.md, experiments/mutants.sh, design-review-001..005, design-refute-001..005, harvest.md; tickets c0175 c0248 c0249 c0250 c0251 c0252 c0253 c0254 c0257 c0260 c0261 c0262 c0263 c0265 c0267 c0268 (worktree); the in-flight preps on origin after `git fetch`: `origin/prep-work-heartbeat` (c0265, 05263daf), `origin/prep-model-tiers-cheap-sharp-wait` (c0261, cd605d96, "prepared after review 009", `design: ready`), `origin/prep-capture-interview-and-idea-review` (c0260, ef3fff1b), `origin/prep-full-force-final-review` (c0262, aeb19498); open PRs `R0083-project-board` (c0118) and `omarchy-board-app` (c0257, no README change).
Round 2 of the combined design. Round 1's answers hold: `no_models()` is in AC6 with the five sub-sections, the two extra vocabulary pins (`it never orchestrates on an expensive one`, `and a person approves it`) are there, the follow-up paragraph and items 1 to 3a match the draft, and F4's two wordings are in. None of review 005's findings is reopened.

Runs (all through `./zn run --time <s> --`, in a scratch clone `.cache/rev006` of the worktree with the checkout's `origin/main` fetched in; no commits, so no identity was needed; the clone was removed afterwards and `git status --short` in the worktree is clean):
- Draft applied as Implementation step 1 says (base README up to `## How it should work`, the draft's `## Intent` to before `## The five parts`, the base from `## The five parts`): byte-identical to `experiments/README.draft.md`. `./zn check c0264`: 10/10.
- My mutants of the draft (perl over the draft as the README, then `./zn check c0264`), every one **10/10, survives**:
  - `final-reviews-cheap`: Intent "Expensive models do every final review;" and Models "- Expensive models do every final review:" become "Cheaper, faster models do every review, the final ones too", and The full-force review "It runs on an expensive model" becomes "on a cheap model".
  - `no-idea-review`: The idea stage loses "and a clean adversarial reviewer on an expensive model checks that it says what the person said: nothing dropped, added or bent", and Intent loses "has it checked against what they said".
  - `rank-over-depends`: Order loses "`depends_on` is a hard constraint; `rank` only orders what is free, so the order works around a blocked item without changing any rank", and "whose `depends_on` are all done, which is not blocked" becomes "whose rank is lowest".
  - `human-start-ranked`: Order loses ", even when a person started it without changing its rank".
  - `full-force-not-fresh`: The full-force review loses "on an expensive model in a fresh context".
  - `stays-after-block`: an added "It keeps its context." after "It lets go of a raft only when the raft is blocked." (I do not raise it as a finding: an added contradiction is step 5's diff, as review 005 F2 said.)
- The 29 recorded mutants were not re-run (all killed, per E4).
- Capture: `./zn capture c0264` prints c8c78404 with no marker. The Problem only gains detail and the three `Decided with the user (2026-11-08)` paragraphs. Scope holds, except that F2's rules have a Design and no working criterion.
- Other preps' README plans (the search, pasted): `git grep -n -i README origin/<prep> -- z-nile/.tracker/issues/<id>/` for each of the four preps above, then reading the hits:
  - c0261 `acceptance/docs.spec.luau:114` `absent(readme, "round one Opus through \`claude\` or \`agent\`", "README")`, `:144` `absent(..., "round one on", ...)`, `:145` `absent(..., "round two \`grok-4.7-xhigh\`", ...)`, `:113` a "Models per activity" bullet in The five parts, `:130-131` the dispatcher bullet; c0261.md:157 lists `z-nile/README.md` in Touched modules. These are promoted cases (in `acceptance/`, marked "(rule)").
  - c0265 `check.sh:27` `sed -n "/^### Order/,/^### /p" ... | grep -qF "./zn lost"`, `check.sh:30` `grep -qE "^\| .* \| c0265 \| exists \|"`; c0265.md:168 Touched `z-nile/README.md`; c0265.md:27 "the README's Order puts lost before rank". Both lines are check.sh only, so nothing in the gate keeps them after c0265 is done.
  - c0260 `experiments/prototype.patch:152-160` adds the Roadmap row `| capture interview and idea review (sections of the issue, \`zz-review --mode idea\`) | c0260 | exists |`; `acceptance/skills-restated.spec.luau:57` requires a `| c0260 | %a+ |` Roadmap row (promoted).
  - c0262: no README in its Touched modules or specs.
  - `grep -n -F -e 'round one Opus through \`claude\` or \`agent\`' -e 'round two \`grok-4.7-xhigh\`' -e './zn lost' experiments/README.draft.md` → only line 104 (both round phrases); there is no `./zn lost`.

### F1 [high] Implementation step 1 replaces How it should work wholesale, and steps 2 and 5 forbid keeping anything else. Three in-flight preps plan edits inside that section, so in some landing orders c0264 reverts their delivered text or turns a promoted spec red, with `Overrides: none`
Where: c0264.md Implementation steps 1, 2 and 5; E3 ("which open branches touch the README?"); "Where the two preps disagree" items 2, 3 and 3a; AC6's "c0251's older line ... is c0251's to reword"; Existing work ("Every labelled item other than c0117 and c0118 is a draft whose own prep comes after this README and reads it").
Evidence: the pasted search above. For each order:
- **c0261 delivered first.** c0261's prep is `design: ready` ("prepared after review 009"). Its promoted `docs.spec` fails on any README that contains "round one Opus through `claude` or `agent`" or "round two `grok-4.7-xhigh`". Draft line 104 contains both. Step 1 puts them back and step 5 makes keeping c0261's wording a code-review finding, so c0264's gate goes red on a promoted spec that Overrides does not name. The executor is then stuck: the fix is a change step 5 forbids.
- **c0265 delivered first.** c0265 adds `./zn lost` to Order and a `| c0265 | exists |` row. Step 1 deletes the `./zn lost` line, and only c0265's check.sh pinned it, so the gate stays green and the regression is silent. Step 2 then flips the draft's c0265 row and the label on Claiming across hosts to *exists*. That stamps *exists* on the draft's own heartbeat sentences ("the old worker's work is kept, and a numbered copy of it continues the work"), which item 3a says c0265's prep reads differently: the old worktree stays at its path and its branch is renamed. Every label AC7 compares agrees with the tracker, but the sentences under them describe something c0265 did not build. This is the lesson's "for each sentence labelled `exists`, which file or command proves it?"
- **c0264 delivered first.** c0260's patch and c0265's plan each add a second Roadmap row for their id, so AC10 (`roadmap-unique`) turns their gates red. That is AC10's purpose. But the design tells only c0265 to flip the existing row instead (item 3a), not c0260. And it says c0251 rewords the round-one line, when c0261's prep is the one that removes it.
- E3 could not find any of this: it diffed each remote branch's `z-nile/README.md`, and a prep plans its README edit in a patch, a check.sh or a spec, not on the branch. Review 005 F3 already found a hole in this list's coverage (c0265's prep only). This round finds it in three more preps, so the method is the problem: a hand list of the preps the author has read.
Critique: z-design/quote-other-preps-before-promising asks "for each order the two could land in, which sequestered or promoted specs turn red?", and z-design/design-the-execution-window asks the same about main changing under the raft. The tempting fix is to add c0261 and c0260 to item 3. That records the problem and leaves steps 1, 2 and 5 still reverting whatever lands first.
Consequences: a three-way merge keeps another issue's lines, and then a few pins can meet them. Two checks.
- AC9's diagram and AC6's vocabulary: none of the three preps touches either (c0261 edits Reviews by different models and The five parts, c0265 adds a line to Order, c0260 adds a row), and the LABELS list holds no prose text. So the merge passes c0264's check.sh in every order above, as long as the executor keeps one row per id (AC10) and the state the tracker gives (AC7).
- A flip to *exists* (step 2) needs the delivered issue's own text. When that issue's PR already rewrote the sentence, its version wins. When it did not, the executor escalates instead of stamping *exists* on the draft's wording.
Recommendation:
- Re-run E3 as the search pasted above, over every open `origin/prep-*` branch's issue folder as well as the branches' README diffs, and record the hits.
- Rewrite step 1 as a three-way merge: `git merge-file` of main's README at delivery, the README at this prep's merge-base, and the draft. Inside the two sections, keep every line another landed issue changed. Step 5 then allows "a line a landed issue's PR wrote" beside a state word.
- Step 2: an issue that is done by delivery keeps its PR's wording of the sentences it labels. Where the draft's sentence would need *exists* and no landed text backs it, stop and escalate (zz-execute stop conditions).
- In "Where the preps disagree", put c0261's removal of the round-one line (c0261's promoted docs.spec, against c0251's Scope decision line) and c0260's planned second row (it must flip c0264's row, AC10) beside item 3a. Correct AC6's and item 3's "c0251's to reword" to name both tickets.
- Add one mutant per order to mutants.sh and E4 as correct variants that must pass 10/10 after the merge:
  - main with c0261's README hunks applied first;
  - main with c0265's `./zn lost` line and exists row first.
- Run c0261's `docs.spec` README cases (lines 113-114 and 144-145) on the merged README of the c0261-first variant.
Lesson: z-design/quote-other-preps-before-promising

### F2 [high] Four rules from the user's ask that the Design lists as stated have no pin, so a README that drops or reverses them passes all ten criteria
Where: Design, "The user's rules the text states" ("a real model for each command and activity, expensive on every final review, the cheapest for waiting"; "the capture interview and idea review"; "rank (... lost first, around `depends_on`, ...)"); AC6 ("states the rules of the worker model in the user's terms (the vocabulary in check.sh)"); check.sh lines 125-136; draft lines 27, 30, 69, 84, 85, 99, 110.
Evidence: `final-reviews-cheap`, `no-idea-review`, `rank-over-depends`, `human-start-ranked` and `full-force-not-fresh` above each give 10/10. In order:
- The ask's first economy rule, "use sharp expensive models for all final reviews", is in no AC6 phrase. "Expensive models do every final review" occurs twice and is pinned nowhere, and AC2's "expensive" is still met by "An expensive model never orchestrates".
- c0260's "reviews that in a clean adversarial agent to make sure that the written out idea actually corresponds" is pinned nowhere. 'verbatim', 'every question z-ticket asked with its answer' and 'confirms the idea' all survive the deletion.
- c0249's "We also recognize depends on to ensure that we work around rank when something is blocked" and "even if a human went and started the thing without updating rank" are pinned nowhere. 'Lost work comes first' stays when the clause after it goes.
- c0262's "fresh context" and "expensive model" are pinned nowhere; 'limited view' sits in the same sentence and survives.
Critique: this is the hole review 005 F2 found (rules pinned in one place only), now as rules pinned in none. So the problem is how the vocabulary was built: it was picked phrase by phrase, not derived from the Design's rules list. A Checked criterion that says "the rules of the worker model" passes a README that runs final reviews on cheap models, which is the opposite of the Intent's cost rule. Leaving it to step 5's diff makes AC6 a Judged criterion in practice. The tempting fix is to add these four phrases. Then the next round finds a fifth.
Consequences: a derived pin set needs one phrase per rule, each occurring where the rule is stated. The two-place rules ("Expensive models do every final review" in Intent and Models) need a pin in each place, or a count ≥ 2, because a single grep is met by either copy. Pins catch removal and rewording only; added contradictions stay step 5's.
Recommendation: build AC6's vocabulary from the Design's rules list item by item. Add a column to the Rules and mutants table, or a short table under it, mapping each item of "The user's rules the text states" and each bullet of the Problem's "How it should work describes" to its pinned phrase(s) and a deletion mutant. At least add:
- 'Expensive models do every final review' (both occurrences: count them, or pin the Intent copy as '**It stays cheap.** Expensive models do every final review');
- 'a clean adversarial reviewer on an expensive model checks that it says what the person said';
- '`depends_on` is a hard constraint';
- 'works around a blocked item without changing any rank';
- 'even when a person started it without changing its rank';
- 'It runs on an expensive model in a fresh context'.
Add `final-reviews-cheap`, `no-idea-review`, `rank-over-depends`, `human-start-ranked` and `full-force-not-fresh` (substitutions as in the runs above) to mutants.sh, E4 and the AC6 row. The unchanged draft is the correct variant.
Lesson: z-design/spec-design-correspondence

### F3 [low] The Design's heartbeat bullet still says the worktree is renamed, which the draft no longer says
Where: c0264.md Design, "**Claiming across hosts** gains the heartbeat (c0265): ... and the old worker's worktree is renamed and a numbered copy continues the work"; draft line 91 ("the old worker's work is kept, and a numbered copy of it continues the work"); item 3a ("The README says only that the old worker's work is kept").
Evidence: `grep -n -F -e 'worktree is renamed' -e 'its worktree is kept' c0264.md experiments/README.draft.md` → c0264.md:87 only. Round 1's F3 answer changed the draft and item 3a but not this Design sentence.
Critique: step 5 has the code reviewer diff against the draft, but an executor reading the Design may "restore" the rename. The rename is exactly the wording c0265's prep reads differently (item 3a).
Consequences: none on the checks.
Recommendation: make the Design bullet say what the draft says ("the old worker's work is kept, and a numbered copy of it continues the work").
Lesson: z-design/restated-rules-move-together

### F4 [low] AC6's check label still claims "no model names" over the whole README, and the diagram puts heartbeat branches on `origin/main`
Where: check.sh line 125 (`"AC6: ... and names no tiers and no model names"`) against c0264.md AC6 (scoped to five sub-sections, with c0251's line excepted); diagram.txt / draft line 45 (`stack[("ranked stack on origin/main: tickets, rafts, state; heartbeat branches")]`) against draft line 91 ("as a commit on a heartbeat branch, not on `main`").
Evidence: review 005 F1's Recommendation said "Reword AC6 (doc and check label)". The doc was reworded and the label was not, while the README the label judges says "author Sonnet, round one Opus". The diagram's node lists heartbeat branches inside the thing it names "on origin/main".
Critique: z-design/spec-design-correspondence asks whether every check's label says exactly what its command verifies; this one says more. The node invites the reading "heartbeat on main", which the user decided against.
Consequences: diagram.txt is pinned word for word (AC9) and sequestered, so the node changes in the prep, with diagram.txt and the draft together.
Recommendation: label AC6 "... and names no tiers, and no model names in Intent, The idea stage, The worker, Models per command and activity and The full-force review". Reword the node, for example `stack[("ranked stack on origin/main: tickets, rafts, state; heartbeat branches beside it")]` or `"... state; heartbeats on their own branches"`, in diagram.txt and the draft both.
Lesson: z-design/spec-design-correspondence

### F5 [low] Round 1's candidate lesson was not harvested
Where: harvest.md (design-review-005 F1 → z-design/spec-design-correspondence); `git diff origin/main...HEAD -- z-nile/skills` adds lines only to quote-other-preps-before-promising and status-labels-need-a-tracker-fact.
Evidence: review 005 offered a candidate ("a port of a user decision of the form 'the text says no X' re-runs the old mutants for X and adds one that brings X back"). harvest.md has no `- note` line for it, and spec-design-correspondence gained no note.
Critique: the zz-review skill's Lessons section asks the lead to record a subagent's candidate as `- note <what happened>: <lesson ids>`. Mapping a finding to an existing lesson without adding the note leaves the lesson unchanged.
Consequences: none.
Recommendation: add the note to spec-design-correspondence (or a new lesson) and a `- note` line in harvest.md.

## Lessons (candidate, for the lead)
- A search for other preps' edits to a shared document reads their plans, not their branches' copy of it: a prep's README edit lives in a patch, a check.sh or a spec until it delivers. Check: did the "who else edits this file" search grep every open `origin/prep-*` issue folder for the file's name, as well as diff each branch? (F1: E3 diffed branches' `z-nile/README.md` and missed c0260, c0261 and c0265.)
- A vocabulary pin list is derived from the Design's list of rules, one phrase (and one deletion mutant) per rule. Check: for each item of the Design's "rules the text states", which pinned phrase dies when that rule is deleted? (F2.)

Verdict: changes

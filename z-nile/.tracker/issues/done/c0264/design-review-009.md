# Review 009: c0264 (design mode)
Inputs: worktree `prep-c0264-reprep` at origin/main 5a76e79d (uncommitted prep files, sha256 prefixes): c0264.md d81e4a0433d7, check.sh db10c345dbc4, acceptance/intent.spec.luau 4479d6dbfe56, acceptance/roadmap-unique.spec.luau 71f5716117fe, diagram.txt 0d9c64933180, legend.txt e2674ffca3b3, experiments/README.draft.md 4fd6a41866ad, experiments/README.base.md 9384aa0e6b7c (equal to origin/main's README), mutants.sh 0a5845d15a9f, merges.sh 625f0747a113, branches.sh bac5759c9750. Read `./zn capture c0264`, design-review-001..008 and their refutes, the tracker documents of every labelled id, `.models.toml`, `z-nile/engine/{models,idea,contract,approval,openlist,trace}.luau`, `main.luau` (status, approve, ready, done) and the zz-review, zz-rules, zz-execute, z-design and z-ticket skills. Ran a scratch copy of check.sh's AC6 to AC9 against the draft through `./zn run` (all pass), diffed the draft's diagram against diagram.txt (equal), re-ran E3b without its fetch (the same 20 branches and counts), read the eight conflicting branches' README diffs and PR #318.

### F1 [high] Four `*exists*` sentences say what main does not do, and AC6 pins two of them, so the executor cannot correct them
Where: README.draft.md:106, :112, :146, :190; check.sh:159, :172
Evidence:
- draft:106 "Every review has its own role on an expensive model, and a challenger never runs on the model that wrote the text it challenges ... *exists*". On main `design-challenge` names no `author` and runs on `claude-opus-5-5`, the same model as `design` (.models.toml:6-7, :53-69), and a raft's review has no role of its own: `models.roleFor` returns `"raft"`, the author's own role (models.luau:356-366; zz-review SKILL.md:18 says the same in its next sentence).
- draft:112 "today a challenger's role names an `author`". Only `idea-challenge` and `code-review` do (.models.toml:50, :96).
- draft:146 `./zn approve` "records the person, a hash ..., and their words in the issue's `approval.md`". The format is `when who hash parts` (contract.luau:14-19; `cmd.approve` writes nothing else). "the user's words" is c0283's outcome (c0283.md:17), so a captured clause rides an `*exists*` label.
- draft:190 "`./zn done` lands it with one bind after the final review and one full gate". `done` runs `z-nile/check.sh --affected` (main.luau:5127-5128, zz-rules SKILL.md:100). For a game, the full gate runs after `done`, in a clone (zz-execute SKILL.md:90). "with one full gate on its top" is c0248's Q4 and c0253's Q2, both captured.
- Smaller: draft:69 says `./zn status <id> preparing` is refused until the review is ruled. That holds only for a ticket with an `idea:` key (idea.luau:29-31, :321-323).
Critique: the Solution is "nothing new is described as built" (c0264.md:62), and AC7 trusts every `*exists*` with no id ("want=exists", check.sh:131). So these four pass every criterion. Step 5 tells the code reviewer to accept the draft's text, and the phrases at check.sh:159 and :172 are sequestered, so the executor has to deliver them as they are. The easy fix is to soften the wording ("most reviews"), which leaves "their words" and "full gate" in place.
Consequences: rewording changes two AC6 pins and two mutants (`final-reviews-cheap-section` mutants.sh:40 and `stack-lands-bottom-up` :74 anchor on the old text), and E4 runs again. Moving "full gate" and "words" under their tickets adds no label, because each joins a sentence that already has one, so LABELS is unchanged. zz-review SKILL.md:18 contradicts itself ("A challenge is never run by the model that wrote the text", then the design-challenge exception). That sentence is outside this issue (AC8, skills untouched), so the lead should capture it.
Recommendation: state what main does.
- draft:106: "Every review runs on an expensive role: `idea-challenge`, `design-challenge`, `code-review`, `final-review`, and `raft` for a raft's review. `idea-challenge` and `code-review` name the role that wrote the text as their `author`, which drops that model; `design-challenge` and a raft's review run on the same model as their author. *exists*"
- draft:112: "today `idea-challenge` and `code-review` name an `author` ...".
- draft:146: drop "and their words". draft:147 becomes "The approval is also a row of the record, with the person's words, and `prepared` is refused until it has run. *captured* (c0283)".
- draft:190: "... and `./zn done` lands it with one bind after the final review and the affected gate". draft:191 (c0248) gains "and the stack lands with one full gate on its top".
- draft:69: "for a ticket captured since (one with an `idea:` key)".
- Pins: re-pin AC6 (check.sh:159, :172) to the new phrases. Add AC6 negative checks: the `*exists*` approve line has no "words", and the Stacked delivery `*exists*` sentence has no "full gate".
- Mutants: `approve-records-words` and `done-full-gate-exists` (put each clause back; both must fail AC6). Re-anchor mutants.sh:40 and :74 and re-run E4.

Lesson: z-design/status-labels-need-a-tracker-fact

### F2 [high] The draft contradicts the user's 2026-11-11 ruling "a person rafts", and Open to the human does not list it
Where: README.draft.md:27, :90, :102; diagram.txt (engineer end); check.sh:175; c0264.md:225 (R6)
Evidence: c0249.md:38, c0253.md:38 and c0254.md:25 each record Q1 "Rafts + design drafts": "a worker carries rafts from rafted to merge (z-ready, z-run, reviews, merge) ...; a person rafts, so z-raft can ask the rank". The draft says otherwise in four places:
- Autonomous delivery: "once a person has approved its design, an item is rafted, executed, ... with no human in the loop" (draft:102).
- Order: "with no one to answer, the rank stays unset" (draft:90, pinned at check.sh:175, killed-mutant `rank-asked-of-no-one`).
- Intent: "those are the only two stages that ask a person for anything" (draft:27).
- The pinned diagram has no z-raft at the engineer end.

R6 says the draft follows the 2026-11-11 interviews and lists the other half of Q1 (drafting a design) but not this half.
Critique: the re-prep exists to follow main and the tickets as they are today (c0264.md:67-72). Here a recorded user decision is reversed in the deliverable and pinned by AC6 and AC9. Review 003 F2 settled rank-asking for unattended rafting, before this ruling existed. The tempting fix is to drop "with no one to answer", which still leaves Autonomous delivery and the Intent saying no person rafts.
Consequences: following the ruling touches the Intent (the user's own words), the word-for-word diagram (AC9) and three AC6 pins. Main's dispatcher still rafts unattended (zz-rules SKILL.md:184). That is *exists* behaviour the README does not describe, so no label is false, but the target and main differ, and the user should see that.
Recommendation: escalate to the user, as a new Open-to-the-human bullet (see F7 for its form):
- (a) Follow Q1.
  - Autonomous delivery: "once a person has approved its design and rafted it, an item is readied, executed, code-reviewed, full-force reviewed, tested and landed with no human in the loop".
  - Order: "z-raft asks the person who rafts for the raft's rank; unset is a valid answer".
  - Intent: name rafting as a person's step, e.g. "Apart from rafting, resolving a block and giving a rank ...".
  - diagram.txt: the engineer end gains `raf["z-raft: rafts and rank"]` with `des --> raf`.
  - Re-pin AC6 and AC9, rewrite mutants `rank-asked-of-no-one`, `autonomy-skips-approval` and `node-renamed`, and re-run E4 and E3c.
- (b) Keep unattended rafting as the intent. The user then re-rules Q1 on c0249, c0253 and c0254, and R6 says so.

Lesson: z-design/quote-other-preps-before-promising

### F3 [high] The per-ticket full-force review rides c0248's label, though c0262 owns it and lands after c0248; R3 says the draft keeps it, and the draft does not
Where: README.draft.md:29, :117-120, :191; diagram.txt:14; c0264.md:222 (R3)
Evidence:
- c0262's first outcome is "Once per ticket, before its layer merges (c0248), a full-force adversarial review ..." (c0262.md:22). The user's 2026-11-11 ruling says "this review runs once per ticket before the next layer starts, and is part of that layer's completion" (c0262.md:27).
- None of the draft's three c0262 bullets (draft:118-120) says once per ticket. R3 claims the draft "keeps the rest *captured* (c0262)", "once per ticket" included.
- The only per-layer full-force review in the draft is inside c0248's bullet (draft:191: "a layer is complete when it is built, reviewed, full-force reviewed and green"). The diagram's layer node dropped "full-force review" (diagram.txt:14).
- c0262 `depends_on: [c0260, c0248]`, so R-vision (c0248) is done first. At that point c0248's PR flips its label to *exists* (c0248), and AC7 passes a README that calls the per-layer full-force review built.
- Separately, the Intent's "Before a raft merges, a final full-force review" (draft:29) follows #297, not the user's per-ticket ruling. R3 asks about this, but the question rests on R3's inaccurate statement.
Critique: this is the same defect as review 008 F2: after a split, a clause rides a label whose ticket lands before the clause's owner. The tempting fix is to add a c0262 bullet and leave "full-force reviewed" in c0248's line too. Then two tickets claim it, and c0248's label still overclaims once c0248 is done.
Consequences: c0248's line loses the words "full-force reviewed" that the user's c0248 Q1 used. The outcome moves to c0262's line with a cross-reference, so no outcome is dropped, but the human should see it. LABELS gains a fourth `The full-force review|c0262`. If the user picks per ticket, diagram.txt's layer node changes.
Recommendation:
- c0248's bullet: "... a layer is complete when it is built, reviewed and green on top of the layer below; its full-force review is c0262's. ... *captured* (c0248)".
- New c0262 bullet: "- It runs once per ticket, before the next layer starts, as part of that layer's completion. *captured* (c0262)".
- check.sh: add the LABELS row. Pin 'It runs once per ticket, before the next layer starts'. Add a negative check that the Stacked delivery `*captured* (c0248)` line does not contain "full-force".
- Mutants: `per-ticket-dropped` (AC6) and `full-force-under-c0248` (the negative check).
- Rewrite R3 to say exactly what the draft holds. Let the user choose the Intent's "before a raft merges" or "before each ticket's layer is complete". The layer node reads "build, review, full-force review, finish its layer" if the user keeps per ticket (re-pin AC9).

Lesson: z-design/status-labels-need-a-tracker-fact

### F4 [high] If #318 (`engine-z-work`) lands first, step 1's rule drops #318's `*exists*`, and the pinned label map forbids the correct label; E3c's 10/10 shows the check passes the mislabelled README
Where: c0264.md:120 (merge rule), :153 (E3c); merges.sh:30; check.sh:41-83, :125
Evidence:
- #318's README labels its sentence "A person opens any AI CLI and runs `z-work` ... carries it layer by layer to `./zn done`, then stops. *exists*" (`git diff origin/main...origin/engine-z-work -- z-nile/README.md`).
- The rule says "keep the draft's labels and fold the landed sentence in". merges.sh:30 inserts an unlabelled paraphrase ("gets the interactive session worker ... the headless loop does not exist yet"), and the result passes 10/10.
- That README describes a built worker with no `*exists*`, against its own legend ("Nothing below is described as built unless it is labelled *exists*", legend.txt) and the Design's label rule (c0264.md:78). It also leaves "A worker is an AI CLI running `z-work` ... *captured* (c0253)" (draft:76) as the only label on a command that main then has.
- Labelling the sentence correctly adds `Two ends, one stack|-`, and AC7 then fails "label places differ" (check.sh:125).
- #318 is open, and z-work is the way the user expects work to start.
Critique: a correctly labelled README fails AC7 and a wrong one passes it (the review 007 F1 pattern). The tempting fix is "fold it in with *exists*", which the executor can't do without editing check.sh.
Consequences: a second label map is one more pinned set to keep true. It must be chosen by a fact of the merge base, never by the README itself, or a README could pick its own map.
Recommendation:
- check.sh chooses LABELS by `git cat-file -e "$base:z-nile/skills/z-work/SKILL.md"` (the file #318 adds; `base` as in `others`, check.sh:146).
- The #318 variant inserts `Two ends, one stack|-` after `c0117` and `The worker|-` before `c0253`.
- Step 1's engine-z-work rule keeps #318's `*exists*` on its sentence and adds one *exists* sentence to The worker. For example: "Today a person can run `z-work` in the CLI they opened: that session takes one raft to `./zn done`, then stops. *exists*".
- merges.sh's engine-z-work scenario applies that rule to #318's real text and must give 10/10. A mutant that drops the `*exists*` must fail AC7. The base-README (no #318) case still passes with the first map.
- Alternative, which costs another re-prep: the engine-z-work rule becomes a stop condition (escalate for a re-prep).

Lesson: z-design/quote-other-preps-before-promising

### F5 [medium] The roadmap prose lists R-vision's outside dependencies without c0305 and c0306, which #325 put in their place
Where: README.draft.md:187; c0264.md:91
Evidence:
- The draft says "it starts only when every outside dependency of its members is done: c0257, c0260, c0263, c0283 and the heartbeat tickets c0265, c0274, c0275 and c0277", and lists "c0305 to c0307" among "the other worker tickets ... designed one at a time ... and then rafted".
- On main, c0251 `depends_on: [c0117, c0306]` and c0253 `depends_on: [..., c0305, c0283]`. #325 (6ead1904) replaced c0261 with these edges.
- The user's "Keep one raft" ruling (c0248/c0249/c0250/c0251/c0252/c0253/c0254 Q-lines) named c0261. The draft dropped c0261 and named nothing in its place.
Critique: the sentence is a fact about the tracker and is false today. Nothing checks it, so it will drift again at the next edge change.
Consequences: a check that reads `depends_on` at delivery has to follow the tracker the way AC7 does. It reads the working tree's tracker, so it needs the same "merge main first" step as AC7.
Recommendation: name c0305 and c0306 in the dependency list, and take them out of the "other worker tickets" list (or say they come first). Add an AC6-style check.sh line: every `depends_on` of c0248 to c0254 that is outside the raft and not done appears in that sentence. Add a mutant that drops c0306 and fails.

Lesson: z-design/restated-rules-move-together

### F6 [medium] "Nothing expensive orchestrates or waits" sits under c0305's label, but c0305 owns neither half; c0305's own ruling has an expensive lead wait
Where: README.draft.md:108, :81-82; check.sh:160; mutants.sh:35, :50
Evidence:
- c0305's scope is the dispatcher's gate wait. Its ruling "Accept the blocking wait" (c0305.md:18) keeps "a lead waits for its nested review in one blocking command: no wait model for that". Orchestration on a cheap model is c0253's ("It is cheap ...: the worker itself never orchestrates or waits on an expensive model", c0253 Problem, and draft:82).
- When c0305 is done, AC7 flips draft:108 to *exists* (c0305), and the README claims nothing expensive orchestrates, while interactive leads still run on the `design` and `raft` roles (Opus).
- The worker bullets also disagree with each other. draft:81 says the worker waits "with no model running". draft:82 says "its waiting ... runs on the cheapest model". c0253's Q3 and Q6 say a supervisor with no model.
Critique: the "label covers only its own ticket's outcomes" rule (c0264.md:125). The tempting fix is to delete the sentence, which drops a pin on the user's "don't orchestrate and wait on expensive models" (review 001 F3).
Consequences: mutants.sh:35 and :50 anchor on "Nothing expensive orchestrates or waits\.", so they turn BROKEN when it is reworded.
Recommendation: rewrite draft:108 as "... polls it on the cheapest model of the CLI, so no expensive model waits on a gate. *captured* (c0305)". The orchestration rule stays in the Intent (unlabelled) and in c0253's bullet (draft:82, already pinned as 'it never orchestrates on an expensive one'). Bring draft:82 into line with c0253's Q3 and Q6 (the supervisor polls with no model running). Re-pin check.sh:160, re-anchor mutants.sh:35 and :50, and re-run E4.

Lesson: z-design/status-labels-need-a-tracker-fact

### F7 [medium] R1 to R7 are bullets the open-list gate cannot see, so `./zn approve`, `status prepared` and `ready` pass with them unruled; R1, R3 and R4 change captured outcomes without a recorded decision
Where: c0264.md:219-226; openlist.luau:99; c0264.md:17-56
Evidence:
- `openlist.pending` reads only `- F<n>:` and `- JC<n>:` bullets (openlist.luau:99). `- R1 (Model tiers ...)` is never pending. `cmd.approve` refuses only on pending bullets (main.luau `approve`: "has an unruled open-list bullet"), so R7's "after ruling R1 to R6" is not enforced.
- Three of the bullets change a captured outcome:
  - R1 relabels the captured "Model tiers (c0261)" (c0264.md:30) as c0305.
  - R3 changes the Intent's full-force timing.
  - R4 changes the user's "reviewing back and forth".
- The Problem has no `Decided with the user` line for any of them, though the c0261 ruling can be quoted: "Retire, file leftovers" (c0305.md:18).
Critique: z-design keeps scope changes as `Scope decision`/`Decided with the user` lines, and the gate only enforces `F`/`JC` bullets. As written, nothing stops an approval while the scope changes are unruled.
Consequences: if the author answers this finding "disputed" or leaves it open, its own `- F7:` bullet under Open to the human is enforced, and the R items can be listed in it.
Recommendation:
- Ask the user R1 to R6 (and F2, F3) before the prep commit. Record each answer as a `Decided with the user (2026-11-1x)` line in the Problem; R1 quotes "Retire, file leftovers" and the user's choice of the section's label.
- Keep under `## Open to the human` only `- F<n>:` bullets.
- If the user cannot be asked now, put the open questions in this review's ids (`- F7: R1 ... R6. Decision: ...`) so `openlist.pending` blocks approval until they are ruled.

### F8 [medium] Step 2 says a ticket that left the tracker "loses its row and its labels", but check.sh pins every row and label, and R5 itself offers to withdraw c0283
Where: c0264.md:214 (step 2), :224 (R5); check.sh:41-111, :125-127
Evidence: LABELS and ROWS are fixed lists, compared exactly (check.sh:125, :127). If c0283 is withdrawn (R5's own option), or a labelled ticket is split or renumbered, step 2's correct README fails AC7 ("roadmap issues differ"). The executor may not edit check.sh. c0261 left the tracker this week, and that is why this re-prep exists.
Critique: the documents tell the executor to do something the sequestered check refuses. The tempting fix is to make truth() skip ids that `real` reports `missing`. That lets a stale row for a missing id be removed silently, and it needs a fixture tracker to test.
Consequences: a stop condition costs a re-prep when a ticket leaves. Derived maps cost a mutant that can't run against the real tracker.
Recommendation: step 2 says that a labelled ticket that left the tracker, or a ticket newly split from a labelled one, is a stop condition: escalate for a re-prep (zz-execute stop conditions), since the label map is pinned. R5 states that cost next to "withdrawn".

### F9 [medium] The promoted AC4 pins c0305, a capture from 2026-11-12 with `idea: unchallenged`, the same kind of pin that c0261's withdrawal just broke
Where: acceptance/intent.spec.luau:90; c0305.md:11
Evidence:
- AC4 requires `%*%a+%* %(c0305%)` in Models per command and activity, in a spec promoted to `z-nile/tests/acceptance/c0264/`.
- c0305 has not had its idea challenge. Its own ruling "c0252 builds it" invites a fold.
- If c0305 is withdrawn, folded or renumbered after c0264 is done, the gate goes red and needs an override chore. A label naming c0306 or c0307 in the same section would satisfy AC4 just as well.
Critique: a promoted case should assert the rule (the section carries a ticket label), not today's member. The exact id is already pinned in check.sh's LABELS (sequestered, not promoted).
Consequences: `c0305-unlabelled` then survives AC4 (c0306 and c0307 still label the section), but AC7 kills it. The table row moves.
Recommendation: the promoted AC4 asserts that each of the five sub-sections carries a state label naming an issue (`%*%a+%* %(c%d%d%d%d%)`), at least for the Models section; consider the same for the other four pairs. The exact ids stay in check.sh. Update AC4's wording (c0264.md:198), the Rules row and E4.

Lesson: zz-test/promoted-specs-pin-rules-not-sets

### F10 [low] Three other tickets' captured lines change wording with no entry under Open to the human
Where: README.draft.md:77, :112, :142, :173; c0264.md:81, :86
Evidence:
- c0251's "so rounds rotate" (c0251 Problem, line 19) is removed from its line, while its Q1 and Q3 still rule on rounds.
- The worker's "delivering it as a PR stack" (the user's words, c0264.md:26) becomes "a stack", on the stated ground "not a 'PR stack' of independent PRs" (c0264.md:81). #296's layers each have a draft PR ("Each layer is one branch, one commit and one pull request", zz-rules SKILL.md:74, :81), so the user's term was accurate.
- Provenance and its row name `./zn record`, but c0263's prototype ships `./zn provenance record` (`origin/proto-c0263-raft` ba353845, its README's Provenance line). "./zn record" appears in no c0263 document.
Recommendation: keep "so rounds rotate" in c0251's line, or list it for the user. Keep "PR stack" (draft:77, "delivering it as a PR stack, one ticket at a time"). Name the record command as c0263's prep has it, or write "the record's command".

### F11 [low] Records that do not match the files
Where: c0264.md:76, :111, :152-154, :186
Evidence:
- The Rules table's AC6 row omits the correct variant `c0265-lost-line` (mutants.sh:47), though E4 lists it.
- Existing work says "E3c ran three of them" (c0264.md:111). merges.sh runs four scenarios, and E3c records four.
- E3c resolves only four of the eight conflicting branches. proto-c0275 and proto-c0277 land three or four `exists` rows at once (c0265, c0274, c0275, c0277), which the "keep the landed rows' words" rule has not been run against.
- "Intent ... with one change" (c0264.md:76) lists two.
- E3b's record does not say it ran through `./zn run`.
Recommendation: fix the table, the count and the sentence. Add proto-c0277 (the largest row set) as a merges.sh scenario, run under `./zn run`, and record that E3b ran bounded.

Verdict: changes

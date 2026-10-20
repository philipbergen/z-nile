# Review 005: R0040 (design mode)
Inputs: prep worktree at 36b83a2 plus its uncommitted changes (R0040.md, check.sh, harvest.md, design-review-001..004.md, design-refute-001..004.md; c0111.md with its Appendix, check.sh, acceptance/*.spec.luau; the 12 lesson files under .claude/skills/*/lessons/); scripts/tracker/main.luau, the skills, tests/, and the open rafts in tracker/rafts. The prototype in .worktree/proto-skill-lessons: its c0111 folder, R0040 documents, ledger and lessons are byte-identical to the prep's. I copied it with its working changes onto a `--no-hardlinks` clone under the session scratchpad (origin removed). On that clone, all six c0111 specs pass (32 cases), `lessons --check` passes ("12 lessons, 22 harvest entries, ok"), `--uncovered R0040` passes ("every finding is covered"), `promote-check R0040` passes, RC1 counts 12, and `scripts/check.sh --full` passes. The prototype's skill diff matches the Appendix text.
Dropped from design-review-004: F1, F3, F4. Each is fixed as design-refute-004 says: note entries plus a refused repeated key, an Appendix with the exact text whose 39 literals trace, and the stale lines updated. F2 is fixed for the approve path. F2 below is the next hole in the same mechanism.
Item 10 (the lessons added or changed since round 4): `architecture/parsers-refuse-ambiguity` and `ticket-prep/required-steps-on-every-path` each state a class that another raft could fail, and each has a usable `check`. The new "How to apply" sentence in `ticket-prep/spec-design-correspondence` is general. No JC1 finding.

### F1 [high] Once R0040 lands, the rafts that are already prepared (R0012, R0030, R0035) can't finish execute-raft Phase 5: `--uncovered` lists their unharvested design reviews, and the Risks section says nothing fails
Where: R0040.md Risks & rollback, first bullet ("A raft prepped or executed under the old skills never harvests. Nothing fails until c0112's gate lands"); c0111.md The skills, execute-raft Phase 5 step 3 and ticket-prep step 5.5; Appendix ("**Confirm the harvest**: … must pass"); ready-raft step 3 (the prompt inlines the execute-raft skill as it is at ready time)
Evidence:
- Today the backlog holds `tracker/rafts/R0012` (5 design reviews), `R0030` (6) and `R0035` (4). All three are `prepared-…` and none has a `harvest.md`. `active/R0034` (3 reviews) is in the same position if it is ever stopped and readied again.
- `lessons --uncovered <id>` lists every finding of every `design-review-NNN.md` and `review-NNN.md` in the item. The lessons-cli fixture's R0010 shows this, and so does the prototype's `uncovered`.
- After R0040 merges, readying R0012 inlines the new execute-raft. Its Phase 5 step 3 says `scripts/tracker.sh lessons --uncovered R0010` "must pass" before `done`. For R0012 that command exits 1 and lists every design finding R0012's prep produced. The executor then has two choices:
  - harvest five rounds of another author's design review, which is unplanned work outside its Touched modules and judged by nobody in design mode;
  - escalate, although that failure is not in the stop-conditions list.
- A prep that is mid-round when R0040 lands hits the same wall at step 5.5.
- So the Risks bullet is wrong. The failure arrives as soon as R0040 merges, not when c0112's gate lands. Order & dependencies names these same open rafts but considers only `renderPrompt` and the template.
Lesson: ticket-prep/no-check-red-between-steps (a check that depends on work some items never did)
Critique: This regresses the existing pipeline for three named, prepared rafts. The tempting fix is to soften Phase 5 step 3 to "should pass", or to exempt design reviews from it. Either makes the confirmation pass in the very case it exists for, so a raft that skipped its harvest would pass. That is the `testing/no-vacuous-pass` class.
Consequences: Any honest fix needs one new rule for items whose reviews predate the mechanism. It needs the following:
- a way to recognise those items (for example a raft prepared before R0040's merge, or a raft with review files but no `harvest.md` entry for any design round);
- someone to own the backfill: the item's executor, c0112, or a ready-time refusal;
- a decision on queue order: c0112 is prepped only after R0040 lands, so the gap lasts at least one full raft.
Each choice interacts with c0112, which backfills "every finding in the tree". If an executor harvests R0012 first, c0112 has less to do. If an executor marks the findings one-off, c0112's lessons lose those sources.
Recommendation: Pick the owner explicitly and write it in the Design and the Appendix. The option that holds without a user decision: execute-raft Phase 5 step 3 says "a raft whose prep predates lessons (design reviews and no design-review entries in `harvest.md`) harvests those rounds here, as Phase 4 step 5 does, before the confirmation", and ticket-prep 5.5 says the same for a prep's earlier rounds. Then:
- Pin the sentence in skill-docs and add a Rules row (mutant: the sentence dropped).
- Rewrite the Risks bullet to name R0012, R0030 and R0035 and the cost they take on.
- Shrink c0112's scope note to the items that are done.
The alternative is a user decision on order: c0112 runs before any of those rafts is readied, and Order & dependencies says so. Record whichever is chosen.

### F2 [medium] (repeat of design-review-004 F2) A blocked or taken-over stream never reaches the "Merge the stream" step, so its candidate lessons, and those in its stream reviews, are still dropped
Where: Appendix, execute-raft Phase 2B step 4 ("Then write the candidate lessons the stream reported … read each `stream-review-<issue>-NNN.md` you wrote"); execute-raft Phase 2B step 3 ("a high finding still standing after round 2 means you take that issue over or escalate") and step 5 ("A blocked or unresolved stream is finished by you in the raft worktree (Phase 2A for that issue) … remove its worktree and branch with the same command as in step 4"); design-refute-004 F2 ("at the merge, which every stream passes through")
Evidence:
- Not every stream passes through step 4. A stream that reports `blocked`, or one whose high finding stands after two stream-review rounds, goes to step 5. There the lead finishes the issue itself through Phase 2A and deletes `ws-<issue>`, and no step tells it to squash-merge or to read the stream's report or stream reviews for candidates.
- Those are exactly the streams most likely to have something to teach.
- Phase 5's confirmation (`--uncovered`, `--check`) can't see the loss, because a note is never a finding.
- Round 4 moved this write from Phase 4 to step 4 for the same reason, so this is the second hole in "write the candidates at step X".
Lesson: ticket-prep/required-steps-on-every-path (its check names "a single issue, no streams" but not the blocked branch)
Critique: Per the review skill, a mechanism hit twice gets questioned, not patched again. The tempting patch is to copy the sentence into step 5 as well. That leaves the next branch (a stream escalated in step 3, or an aborted wave) to round 6.
Consequences: If candidates are written when they arrive, that write has to fit step 3's commit rule: "while that file is the only dirty path". So that rule widens to "the stream-review file, `harvest.md` and lesson files". The spend for those lines then goes to the issue's code-review phase, which is correct. A stream's own final report arrives before any merge, so its candidates are written in their own commit, `--issue <issue>`.
Recommendation: Tie the write to receipt, not to a later step. Change the steps:
- In step 3, "when a stream reports (`done` or `blocked`), and when you write each `stream-review-<issue>-NNN.md`, add its candidate lessons as `note` entries (a new lesson file only when none fits) and commit them with that report or file", with the only-dirty-path rule widened to match.
- Drop the step-4 sentence.
Then update the Appendix and skill-docs: pin the phrase inside step 3, between `\n3. ` and `\n4. `. Add a Rules row whose mutant is "the sentence only in step 4", and a case or note covering the blocked branch. Add a source to `ticket-prep/required-steps-on-every-path` and widen its `check` to name "blocked or taken-over".

### F3 [low] The tracker skill's Items text, the format reference both other instructions point to, has no `note` entry and still describes `from` as the way to record any non-review source
Where: Appendix, `.claude/skills/tracker/SKILL.md` block ("optional `from` (a source outside any review)"; "`harvest.md` … has one entry per review finding"); the shared Lessons paragraph and ticket-prep step 5.3, which both say "(format: tracker skill, Items)"; c0111.md Files (`from`: "a source with no item folder … (rare; a prep or raft records such sources as `note` entries instead)")
Evidence:
- A lead who follows the pointer to Items reads that `from` is for "a source outside any review", and that `harvest.md` holds only review-finding entries. A user's correction is such a source, so it gets a `from:` line, and the second correction gets a second `from:`. That is now a `parse` problem (`from is repeated`), and `lessons --check` (AC8 for that raft) turns red.
- Items is the only format summary, and it omits the entry form round 4 added.
- Also, no path in the routing produces a `from` at all. Every lead that can write a file has an item folder, and any other lead captures an issue.
Lesson: ticket-prep/restated-rules-move-together; tracker/exhaustive-lists-name-new-things
Critique: The Appendix is inserted "as written", so the executor will copy the stale text.
Consequences: none.
Recommendation: In the Appendix's Items text, add the note form (`- note <what happened>: <lesson ids>`, a source that is never a finding) and change `from` to "rare: a source with no item folder; use a note otherwise". Optionally pin `- note ` in skill-docs' tracker case.

### F4 [low] Restatements still lag round 4: the typed `Entry` lacks `note`, one Rules row names a mutant the refute replaced, and the note's `<stream>` placeholder is undefined
Where: c0111.md Module (`export type Entry = { item, review, finding, lessons, oneOff }` against the parseHarvest rule "`Entry` gains `note: string?`"); Rules and mutants row "a note is never a finding | … | a note listed by `uncovered`" against design-refute-004 ("replaced by … 'a note covers its item'"); Appendix execute-raft step 4 (`- note <stream> <issue>: <lesson ids>`)
Evidence:
- harvest.spec reads `entries[1].note` under `--!strict`. An executor who copies the typed block fails `promote-check` (RC0), and the fix is spread over two places in the Design.
- The Rules row records a mutant that was not the one run.
- `<stream>` reads as a placeholder for a value nothing defines. The Design's example (`- note ws c0010: a/b`) suggests a literal word.
Lesson: ticket-prep/restated-rules-move-together
Critique: Each is small, but the typed block is what an executor copies.
Consequences: none.
Recommendation: Add `note: string?` to `Entry` in the typed block. Set the row's mutant to "a note covers its item". Write the Appendix form as `- note stream <issue>: …` (and `- note stream-review <issue>-NNN: …` for a stream review's candidate).

### F5 [low] An entry that names the same lesson twice counts as two sources, and nothing refuses it
Where: c0111.md Files (target: "a comma-separated list of lesson ids") and **sources** ("one string per entry naming the lesson"); prototype `sources` (inserts once per id in `e.lessons`)
Evidence: `- design-review-001 F1: testing/pin, testing/pin` gives `testing/pin` two identical sources from one finding, and `--check` says `ok`. The same goes for a note entry, and for `tags: [a, a]`, which `--tags` counts twice. Source count is what the listing and the prompt sort by.
Lesson: architecture/parsers-refuse-ambiguity (its check: "does its parser refuse a repeated or ambiguous field?")
Critique: This is a one-character slip during a harvest, and it silently promotes a lesson.
Consequences: one new `parseHarvest` and `parse` problem.
Recommendation: Make a repeated lesson id within one entry a `parseHarvest` problem (`<item>/harvest.md: <review> <finding>: <id> is repeated`), and a repeated tag a `parse` problem. Add one harvest.spec and one lesson-format.spec case, and two Rules rows (mutant: duplicates kept).

Verdict: changes

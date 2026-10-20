# Review 004: R0040 (design mode)
Inputs: prep worktree at 36b83a2 plus its uncommitted changes (R0040.md, check.sh, harvest.md, design-review-001..003.md, design-refute-001..003.md; c0111.md, check.sh, acceptance/*.spec.luau; the 10 lesson files under .claude/skills/*/lessons/); scripts/tracker/main.luau, the skills, tests/. I also used the prototype in .worktree/proto-skill-lessons: its c0111 folder and its lessons are byte-identical to the prep's. I copied it onto a `--no-hardlinks` clone under the session scratchpad (origin removed) and ran everything there. On that clone, all six c0111 specs pass (31 cases), `lessons --check` passes ("10 lessons, 18 harvest entries, ok"), `--uncovered R0040` passes ("every finding is covered"), `promote-check R0040` passes ("promote-check OK"), and RC1's grep counts 10.
Dropped from design-review-003: F1, F2, F3. Each is fixed as design-refute-003 says: there is one identical role-keyed paragraph in all eleven skills, the AC6 label, spec header and Problem bullet are updated, and step 5.3 reruns `promote-check`. F1 below and F2 below are holes in how the role-routed lessons are recorded and when they are written. They are not holes in the routing itself.
Item 10 (the lessons the author added or changed since round 3): `instructions-runnable-where-they-run`, `rerun-skipped-checks-after-edits`, `restated-rules-move-together` and `spec-design-correspondence` each state a class that another raft could fail, and each has a usable `check`. No JC1 finding.

### F1 [medium] A lesson can hold only one non-review source, and the parser silently keeps the last of a repeated key, so stream and user lessons can never show that they recur
Where: c0111.md Files (`from`: "optional, one line"), select ("sources plus 1 for `from`"), The skills (the lead "writes it … with `from:` when it did not come from a review", and "so do the candidates its subagents report"), Rules and mutants (no row for a repeated key); prototype `lessons.luau` parse (`f[k] = trim(v)`)
Evidence:
- Since round 3, the lead writes every stream candidate and every user correction with `from:`. The paragraph also says "Review findings go through the harvest, and so do the candidates its subagents report". A harvest entry must be `<review> F<n>`, though, so a stream's candidate can't be a ledger entry.
- Suppose the second stream, in a later raft, or the user for the second time, reports a lesson that already exists and already carries a `from`. The "prefer a new source" rule then has nowhere to put the second source. On the scratch clone I wrote a lesson with two `from:` lines (and two `when:` lines). `lessons --full dup` prints `sources: user 2026-11-01: corrected it again`, which drops the first source silently. It uses the last `when`, and `lessons --check` still prints `ok`.
- So a correction the user has made five times sorts like a one-off. That defeats the Design's own premise, "The listing's first line is the most-repeated lesson". The lead's other choices are worse: a duplicate lesson, which is sprawl, or overwriting the old `from`.
- Separately, Files says "Any other key is an error" but says nothing about a repeated key, and no spec case or row covers one.
Lesson: none (the format gap is new; `architecture/one-reader-per-format` bears on the fix).
Critique: Sources are meant to be "computed from the ledgers, never written twice" (Maintainability), but non-review sources live in a single frontmatter slot. The tempting fix is to allow repeated `from:` lines, or a `from: [a, b]` list. That makes the lesson parser read the tracker's frontmatter differently from the tracker's own reader, which is the defect class of this raft's own lesson `architecture/one-reader-per-format`. It also scatters sources across two places.
Consequences: If every source lives in the ledger, `harvest.md` needs a second entry form for a source that is not a review finding. `parseHarvest`, `check`, `sources` and the `--full` sources line all have to accept it, and `uncovered` has to ignore it. `from:` then stays only for a lesson whose source has no item folder at all, and since "any other lead" captures an issue, that source is rare.
Recommendation:
- Add a ledger form `- note <text>: <lesson ids>` (for example `- note ws-f0100 stream: testing/seed-every-enumerated-case`, or `- note user 2026-11-01: …`). It counts one source per entry, in the item's `harvest.md`. The paragraph's lead clause and execute-raft Phase 4 step 5 then say to write a stream's or the user's candidate as a `note` entry, plus a new lesson file only when no lesson fits.
- Make a repeated frontmatter key a `parse` problem (`<id>: <key> is repeated`).
- Spec cases: harvest.spec gets a `note` entry that adds a source and is neither uncovered nor a coverage problem, and an empty note text, which is a problem. lesson-format.spec gets a repeated `when`, which is named.
- Rows: "a note entry is a source" (mutant: notes ignored), "notes are not findings" (mutant: a note listed by `--uncovered`), "a repeated key is refused" (mutant: last wins).

### F2 [medium] Stream candidates are written only while answering a code-review round, a step the approve path skips, and stream reviewers' candidates have no path at all
Where: prototype execute-raft Phase 4 step 4 ("If the verdict is `approve` with no findings, go to Phase 5") and step 5 ("Write the candidate lessons your streams reported…"); Phase 5 step 3; c0111.md The skills, execute-raft bullets; c0111.md Files ("`stream-review-*` files … are not reviews here"); the shared Lessons paragraph ("A subagent (a stream, a reviewer…) puts the candidate … in its review or final report")
Evidence:
- The streams report candidate lessons in Phase 2B, but the lead writes them only in Phase 4 step 5. A raft whose first code review approves with no findings jumps from step 4 straight to Phase 5, so every stream candidate is dropped.
- Phase 5 step 3's "confirm the harvest" checks only `--uncovered` and `--check`. Neither knows a candidate exists, so the loss is silent.
- A stream reviewer is a subagent too. Following the paragraph, it puts its candidate in its review text, which the lead files as `stream-review-<issue>-NNN.md`. The Design excludes those files from harvesting, and no step tells the lead to read them for candidates. Those lessons are lost in every raft, whatever the verdict.
- A single-issue raft (like R0040) usually has an approving or minor final code round, so this is the common path, not an edge case.
Lesson: ticket-prep/no-check-red-between-steps (its how-to-apply asks "name when it first runs … and confirm its input exists by then". Here the writing step is placed after the point where the input can be dropped).
Critique: The candidate is written at a step that is conditional on something unrelated: whether the code review had findings. The tempting fix is to repeat the sentence in Phase 5, which leaves the candidates held in the lead's context across a long phase, where they can be compacted away.
Consequences: Writing at receipt means the lead commits lesson files, or `note` entries per F1, during Phase 2B's merge of each stream. Those commits are then reviewed by the code reviewer like any other change, which is good, since JC1 asks for it. Stream reviews get the same treatment, at the moment the lead writes the `stream-review-*` file.
Recommendation:
- Move "write the candidate lessons" into Phase 2B, at the step where the lead merges `ws-<issue>`: write each candidate the stream or its stream reviewer reported, then commit it with the merge.
- Have the lead read each `stream-review-*` file for candidates when it writes that file.
- Phase 4 step 5 keeps only the review harvest.
- Update skill-docs: the phrase sits in Phase 2B's merge step, not in Phase 4.
- Add a row "stream and stream-review candidates are written at merge", with the mutant "the sentence only in Phase 4".

### F3 [medium] skill-docs pins four phrases the Design never states, so an executor who writes the Design's own words fails a sequestered spec (a third round of the same class)
Where: skill-docs.spec.luau:77 (`rerun \`scripts/tracker.sh promote-check <R-id>\``), :89 (`a candidate lesson goes in the final report too`), :91 (`Write the candidate lessons your streams reported`), :122 (`capture a new lesson as an issue`); c0111.md The skills (lines 164, 171, 172, 183)
Evidence: The Design describes these four sentences, and its own wording differs from the phrases the spec searches for:
- line 164: "a rerun of `promote-check <R-id>`";
- line 171: "a candidate lesson goes in the stream's final report";
- line 172: "writes the candidate lessons the streams reported";
- line 183: "any other lead captures a new lesson as an issue". The prototype inserted "must" to get the infinitive "capture" that the spec needs.

On the scratch clone I rewrote the prototype's sentences in the Design's wording. skill-docs then fails 3 of 5 cases: `missing: rerun \`scripts/tracker.sh promote-check <R-id>\``, `missing: a candidate lesson goes in the final report too`, and `missing: capture a new lesson as an issue`. The Phase 4 phrase would fail next. The executor may not edit the spec, has never seen the prototype (it is uncommitted scratch), and must escalate.
Lesson: ticket-prep/spec-design-correspondence. Its check asks "does every sequestered assertion follow from a Design sentence". This is the third round with this class (design-review-001 F6, design-review-002 F4).
Critique: Each round fixed the assertion it was shown, but the mechanism stays the same: the spec pins the prototype's exact wording, while the Design paraphrases it. Every new skill sentence reopens the gap. The tempting fix is to change these four Design sentences to match, which leaves the next added sentence open to the same drift.
Consequences: If the Design carries the exact text, it grows by the inserted sentences, which is about one paragraph of quoted text. In return, the paragraph's identity check, the role clauses and every `at(...)` literal become traceable. A mechanical check makes the rule enforceable in prep: every string literal passed to `at(` in skill-docs.spec must appear verbatim either in c0111.md or in the skill file as it is on `main`.
Recommendation:
- Under The skills, quote verbatim (in a fenced block) the shared Lessons paragraph and every inserted sentence the spec reads: the 5.1 pass, the 5.3 harvest and rerun, the 5.5 confirmation, the Phase 2B brief clause, the Phase 4 and Phase 5 sentences, review item 10, and the AGENTS.md paragraph. Say that the executor inserts them as written.
- Run the literal-trace check above once now and record it in Unknowns & experiments. Add it to the `how to apply` of `ticket-prep/spec-design-correspondence` (a new source for that lesson).

### F4 [low] Several restatements still describe pre-round-3 rules, and the experiment record is stale
Where: R0040.md Whole-raft design line 27 ("every SKILL.md ends with "## Lessons" (read at the start, write at the end)"); c0111.md Solution line 34 ("The skills read their lessons when they start and harvest when they finish"); c0111.md Rules and mutants row "AGENTS.md states the two forms"; Unknowns & experiments line 221 ("OK after round 2's answers") and line 225 ("All 30 mutants fail")
Evidence:
- Since round 3, writing is routed by role, there are three roles rather than two forms, and the harvest happens each round, not at the finish.
- design-refute-003 reports `promote-check` OK after round 3, and 62 mutants with 61 killed. The Design's record still says round 2 and 30 mutants, so review item 0's "check that record" checks a record that is out of date.
Lesson: ticket-prep/restated-rules-move-together
Critique: Each line is small, but an executor reads the raft diagram first.
Consequences: none.
Recommendation: Reword line 27 to "(read at the start; new lessons routed by role)". Reword the Solution sentence to "harvest each review round". Rename the row to "AGENTS.md states the role routing". Update E1 and the mutation record to the latest round's results (count, killed, obsolete) after this round's answers.

Verdict: changes

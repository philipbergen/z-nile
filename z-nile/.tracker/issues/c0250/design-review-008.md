# Review 008: c0250 (design mode)
Inputs: prep worktree `prep-c0250-r2` at HEAD (`git diff 056b13459 HEAD -- z-nile/.tracker/issues/c0250 z-nile/skills`: `design-refute-007.md`, `c0250.md`, `check.sh`, `acceptance/dispatch-block.spec.luau`, `experiments/mutants-r2.py` and `mutants-r2.txt`, `harvest.md`, the lesson note); prototype `origin/proto-c0250-r2` read only (tip 403c62e36 and its diff from 7a43a503a: `engine/dispatcher.luau` `modelStep` and `oneStep` nested stops, `skills/zz-rules/SKILL.md`; `engine/dispatch.luau` `blockCommand`; `tests/lib/fakecli.luau`; c0256's `step.spec` nested-review case).

Round 6 of the back-and-forth, kept narrow as briefed. What holds. The new case "a review started on a layer of a readied raft …" runs where it sits. It comes last in the file, and both cases it relies on are in check.sh's `--run` list ("a dispatched z-run step blocks an active raft" blocks R0010; "a resolved raft's z-run …" resolves `retry`, readies R0010 again and runs one ok z-run). So R0010 and c0050 are `active` on `origin/main` with `blocked:` removed, and `st.carried` is set, so the one-step z-run carries nothing again. The fake logs `args=$*`, so the z-run's own prompt is in the log, but it names `--layer <issue>`, not `c0050`. That means the positive assertion is not met by the prompt. Both mutants die on the case's negative assertions whichever site they touch: a nil raft gives `./zn block c0050 <reason>`, and the issue's folder gives `escalation.md in c0050's folder`. In 403c62e36 the `modelStep` site already passed `nestedRaft` and now names `{nestedRaft or id}'s folder`. Answer F2 holds in "Where c0250 sits" and Design 6, and it matches c0248 outcome 9. The `run (r2)` row cases for the new rows exist and are named exactly. AC8's text is identical in the document and in check.sh, and the Test plan line names the new case. E7 (6) and (8) now say "not met as worded" with per-case reasons, and the counts add up: 12 red files, d0331's five plus seven; c0300 1/5 with AC5 restored on the tip. Four gaps follow.

### F1 [medium] Review 007 F1 is half answered: Design 5 still does not state the message's folder, and the issue-outside-a-raft form names no folder in any case
Where: Design 5 nested-stop bullet (c0250.md:296, "… so the note goes in the raft's folder"); dispatch-block.spec:440-454 (the c0020 case); Rules row "the nested stop names the raft's folder for the note" (c0250.md:655); design-refute-007 F1
Evidence: Review 007 F1 recommended three things: "specify the message's two forms in Design 5, quoting both", "Extend the c0020 case with its folder", and split the row. Only the split and the new raft case were done. Design 5 says what the command is (`blockCommand`). It never says that the message names a folder. Yet the new case pins `writes escalation.md in R0010's folder`, a sentence no part of the Design gives. The c0020 case asserts `./zn block c0020 <reason>` but no folder. Take the mutant `{nestedRaft}'s folder` (the `or id` dropped) in `modelStep`. For c0020, which has no raft, it prints "writes escalation.md in nil's folder", and every case still passes. Its folder row covers only the raft form.
Critique: the tempting fix is to add one `has(log, "c0020's folder")` and stop there. That still leaves a spec assertion that follows from no Design sentence, and an implementer who words the folder differently ("the raft folder", a path) fails a case that the document never asked for.
Consequences: the Design then fixes the folder's wording in both forms. A raft id or an issue id, written as `<id>'s folder`, is the form `block` reads. It is not a path. Any other caller that names the note's folder must use the same words, so the fallback stop and the prompt need checking for the same wording, or the Design must say they name no folder.
Recommendation: in Design 5, quote both forms: "your author writes escalation.md in `<R>`'s folder and runs `./zn block <R> <reason> --layer <id>`" for a member of an active raft, and "… in `<id>`'s folder and runs `./zn block <id> <reason>`" otherwise. Add `t.expect(has(log, "writes escalation.md in c0020's folder")).toBe(true)` to the c0020 case. Widen the folder row to both forms, with the mutant "`or id` dropped (a non-member's folder is `nil`)", and run it.
Lesson: z-design/spec-design-correspondence
Erred: z-design
Upstream: none

### F2 [low] The nested stop's text exists twice in the prototype, and the copy fixed in `oneStep` is reached by no case
Where: prototype 403c62e36 `dispatcher.luau` `modelStep` (the `exProblem` at about line 1998) and `oneStep` (the nested `print` at about line 3503); Design 5 ("the nested stop", singular)
Evidence: `modelStep` moves a nested step's `questions.md` aside (about line 2049) before `oneStep` tests `fs.isFile(st.dir/questions.md)`. So for a model reviewer, the `oneStep` copy, whose `blockCommand(id, nil, …)` 403c62e36 changed to `nestedRaft`, is not reached by the c0020 case or by the new one. The lead's notes in `mutants-r2.txt` do not say which site the two nested mutants changed. A revert of the `oneStep` hunk passes every case.
Critique: this is a maintainability trap more than a defect today. The two copies already disagree on their tails: "(the file is set aside as questions-refused-N.md, unread)" and "(the item is blocked, not this step); the answer reaches …".
Consequences: one helper gives both sites one text. Its pure case can then pin both forms of F1 without a fixture.
Recommendation: have the Design name one pure function for the whole stop sentence (for example `dispatch.nestedStop(id, raft)`, built on `blockCommand`) that both sites call. Alternatively, state that the `oneStep` branch is reached only by a non-model nested step and drop it. In either case, record in `mutants-r2.txt` which site each lead mutant changed.
Erred: z-design
Upstream: none

### F3 [low] E7 (5) says the first mutant each row names was run, but rows 642, 643 and 669 ran their second, and the lead's kills have no output
Where: c0250.md E7 (5) ("the first one the row names"); Rules rows "a step that blocks and leaves `questions.md` …", "a nested step's stop tells its author to block, and keeps c0256's words", "a resolved draft raft's note reaches its issue's next step once"; `experiments/mutants-r2.txt` tail
Evidence: mutant 4 is "questions.md left waiting after a block", the row's second mutant ("the file left waiting"). Mutant 5 is "nested stop drops c0256 words", the row's second ("c0256's words dropped"). Mutant 22 is "raft note carried twice", the row's second ("the note carried twice"). None of those rows' first mutants is in the results. Review 007 F4 asked for the lead's mutants "and its output". The three lines appended to `mutants-r2.txt` are claims only, with no FAIL line and no pass count (E7 says "13 passed" for the nested pair, but the file does not). The default-Layer row still reads "(AC4 and AC6 fail)" without the AC6 case's name, which only E7 gives.
Critique: on reading, the unrun mutants are killed by visible assertions: the c0020 case's `write these questions` negative, the carry assertions after the resolve, and the two-question failure. So this is a record defect, not a gap in the specs.
Consequences: none.
Recommendation: change E7 (5) to "one mutant per row (the second named for rows 642, 643 and 669), the others reasoned: <the assertion>". Paste the FAIL line and pass count of each of the lead's three runs into `mutants-r2.txt`. Name the AC6 case in row 668.
Lesson: z-design/mutant-ids-match-the-runner
Erred: z-design
Upstream: none

### F4 [low] Design 6's new parenthesis names an empty set of rafts
Where: c0250.md:301 ("A raft readied without c0248's `layers: reviewed` marker (every raft readied before c0248 landed and after c0250 did) lands whole")
Evidence: c0248 and c0250 land together, at R0093's one `done`. No raft is readied both before c0248 landed and after c0250 did. And after that landing, `./zn ready` writes the marker. The intended set is rafts readied before c0248 landed that are blocked after c0250 has landed.
Critique: a reader of the round-007 edit could take it to mean that rafts readied after c0250 lack the marker.
Consequences: none.
Recommendation: "(every raft readied before c0248 landed, when it blocks after c0250 has landed)".
Erred: z-design
Upstream: none

Verdict: changes

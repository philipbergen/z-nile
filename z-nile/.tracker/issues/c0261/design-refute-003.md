# Design refute 003: c0261

Answers design-review-003.md (round 2 of the redesign). Answered here: F1, F2, F4, F7 (design; the interactive-lead question is the user's), F8, F9, F10. Not yet answered, to the next round of the prep: F3 (a sequestered control-cli-shaped spec for the chain's running of `z-wait`, with the non-ok outcome decided and a metrics case; the reviewer is right that the harness exists), F5 (a tri-state `Pr.mergeState`, a green-but-UNKNOWN wait, a transient `gh` error not read as a failed check), F6 (E7: measure the wait step's per-turn cost against its cap), F11 (`--model` on the author's own spend lines). The issue therefore stays `preparing`, not `prepared`.

- F1: fixed: the `Overrides:` label is restored.
- F2: fixed: zz-execute Phase 4 step 4 now ends the loop only for an approving round run with `--final` and says a round on the way that approves is followed by the `--final` round; docs.spec pins the new condition and the absence of the bare sentence; consequences: none.
- F3: not answered yet (see above).
- F4: fixed: a pure `parsePr` case (the three `mergeable` values and a missing one); both mutants (never set; UNKNOWN counted as conflict) run and die.
- F5, F6: not answered yet.
- F7: fixed in the design (the worker's session resolves `z-run`'s model and hands every final review to `zz-review`; c0253 must quote it) and the interactive lead's model is Open question 6 for the user; the zz-rules sentence stays and a docs pin for the worker rule is the next round's.
- F8: fixed: Q5 now offers both options with their costs, and the Decided line's exception is stated.
- F9: fixed in part: zz-rules Steps, `dispatch.luau`'s unknown-step text, the README dispatcher bullet and the `main.luau` usage text are reworded (docs cases pin the first and the README); the README line 65 was reworded earlier; the search for each mechanism (`model steps`, `merge gate`, `round one`) is the next round's to paste.
- F10: fixed: c0175 is named in the Chore checklist with the rule it inherits.
- F11: not answered yet.

## Later answers (after the user's answers of 2026-11-08)

- F3: not fully answered, and said plainly: the chain's running of `z-wait` (the fake-`gh` JSON harness of control-cli.spec exists) and the command-level cases for `status prepared` and `done` are listed with named cases in the Design and Implementation steps as the executor's tests first, marked `reasoned` in the table; the pure halves (gate verdicts, the wait loop against a fake `gh`, `parsePr`, `finalround`) are sequestered. The reviewer should judge those rows by reading.
- F5: fixed: `Pr.mergeState` and `Pr.failed` come from `parsePr`; the gate waits for `checks` when not green and not failed, for `mergeable` when green and GitHub is still computing, never for a failed check, a conflict, a draft, a carry; the poll treats a single transient `gh` error as not a failure (three in a row are); spec cases and run mutants for each.
- F6: answered as an experiment: E7 (the executor measures the wait step's per-turn cost against its cap; the classifier refused the probe session here), with the fallback of a larger cap.
- F11: fixed in z-design (the answering line passes `--model <your model id>`, docs case); z-raft's answering line and zz-execute's author lines are the executor's one-word edits listed in the Design.
- Also answered here: the agent fallback list (`fallback` in the table, `models.tries`, `models.available`; the first choice stays Opus so c0117's review-rule case and "who reviews" case do not change); "Commands refuse" (`finalround`, AC11).

## design-review-004 (round 3 of the redesign): status

Answered (bookkeeping): F6 (Q5 restored as a two-option escalation with the note under the Decided line), F8 (Touched modules and a step for `finalround.luau`), F12 (the Rounds line, the `available` row marked `run`, the Decided line for "Commands refuse"; the `settingsOf` fallback's `waitMinutes` is the executor's one-liner). NOT yet answered, for the next prep session: F1 (a fallback on claude or grok must be refused or carry its effort), F2 (the row of a round must be matched exactly: phase and subject), F3 (which spend.md each command reads: origin/main for `prepared`, the branch for `done`), F4 (prototype the two refusals and run the specs that write a round and run `done` or `prepared`; name each red case in Overrides), F5 (squash-rewritten commit times, `firstRoundAt`, a failed lookup, a model upgrade), F7 (the raft's own round), F9 (the dispatcher's model availability: a failed or empty list fails open, an unlisted model is an attempt `missing`), F10 (per-mechanism restatement searches), F11 (one refusal text per kind).

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

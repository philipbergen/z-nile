# Review 002: R0007 (code mode)
Inputs: db505de (`git diff main...HEAD`); `tracker/rafts/active/R0007/{R0007-review-second-order.md,check.sh,review-001.md,refute-001.md,spend.md}`; `tracker/issues/active/c0043/{c0043-review-second-order.md,check.sh,acceptance/*,spend.md}`; `tests/tooling/metrics-rounds.spec.luau`; `.claude/skills/{review,ticket-prep,tracker,testing,architecture,metrics}/SKILL.md`; `scripts/tracker/{main,spend}.luau`; `tests/run.luau`, `tests/lib/t.luau`.
Dropped from review-001: F1, F2, F3, F4
Run: `scripts/check.sh --full` GATE PASSED (331 passed, 0 failed, 55 spec files); `scripts/tracker.sh check c0043` 5/5 PASS; `git diff 0656948 -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` empty (sequestration holds); no sandbox left in `.cache/` after the gate.

What holds after round 1:
- F1: ticket-prep step 4 now has a **Mutation check** bullet (a prototype in a scratch worktree, the mutant applied, the case must fail on an assertion, the result recorded in Unknowns & experiments, and `reasoned` when there's no prototype). Review item 0 matches it. AC3 and AC4 still pin what they should: AC3 needs `0. **Rules and mutants**` before `1.` in `## Design mode`, plus `missing row` and `reasoned`, and requires `Rules and mutants` to be absent from `## Code mode`. AC4 checks `## 3.` and `## 5.`, and the new bullet is in `## 4.`.
- F2: `tests/tooling/metrics-rounds.spec.luau` is `--!strict` and type-checks in the gate. It has no literal require text in strings or comments. Its sandbox is `.cache/metrics-rounds-sandbox`, which differs from AC5's `.cache/c0043-sandbox`, and `tests/run.luau` runs spec files one after another, so the two can't race. `build()` and `rows()` run inside a `pcall`, the sandbox is removed before any error is re-raised, and a stale sandbox is removed first. A describe-time error surfaces as `FAIL … could not load spec`, not as a silent pass. I planted four mutants in a scratch copy, and each one fails the named case on an assertion while the other two cases still pass:
  - (a) no line anchor;
  - (b) the format read from the latest design review;
  - (c) `second-order` if any design review has the line;
  - (d) a `%sConsequences:` anchor.
  So the mutation claim is honest.
- F3: the metrics skill lists the table, says it covers every raft in any state, and treats backlog and active rafts as incomplete.
- F4: the review skill, ticket-prep 5.2 and the tracker skill's directory listing all put design reviews in the raft directory. No other skill names another location.

The `prep draft` commit (da96dd3) contains exactly the F2 spec and the two doc records the refute describes, and nothing from other work. Its one effect on what ships is F1 below.

### F1 [low] c0043's spend record leaves out the 89-line own spec, because it landed in a commit made outside `tracker.sh commit`
Where: `tracker/issues/active/c0043/spend.md` row 6 and totals; `tracker/rafts/active/R0007/spend.md`; commit da96dd3
Evidence: `scripts/tracker/spend.luau` counts `git diff --cached --numstat` outside `tracker/`, so `tests/tooling/metrics-rounds.spec.luau` counts as issue lines. But it was committed in da96dd3 (`prep draft`, no `Issue:` trailer, no spend row). By the time the F2 fix commit 40996c6 ran `tracker.sh commit`, nothing was staged, so row 6 reads `| 0 | 0 | 9.0 |`. c0043's totals say `+36 / -6`, but its non-tracker diff is about +125 lines, so the lines measure misses about 70% of the work. The raft summary, and the spend that `done` appends to the PR body, carry the same figure.
Critique: The metrics skill names `spend.md` as the source of truth for cost per issue, so the undercount ships and will skew any comparison of what second-order rafts cost. It doesn't touch rework (c0043 is a chore). The tempting fix is to edit row 6 by hand.
Consequences: The tracker skill forbids hand edits to `spend.md` ("never edit by hand"). Rewriting history to redo the commit would disturb pushed commits that other sessions have seen. So any correction has to live outside `spend.md`.
Recommendation: Leave `spend.md` alone. Add one line to the raft's "Addressed during execution" (and to c0043's Verification log): "Spend under-reports c0043 by +89 lines: `tests/tooling/metrics-rounds.spec.luau` landed in da96dd3, a commit made outside `tracker.sh commit` by another session; minutes are in row 6." If the user wants the tooling to handle this, file a chore, for example a `tracker.sh` spend correction row. Don't fix it in this raft.

### F2 [low] Review item 0 says `reasoned` rows "had no prototype", but ticket-prep and c0043's own table allow `reasoned` rows next to a prototype
Where: `.claude/skills/review/SKILL.md:62` (design-mode item 0); `.claude/skills/ticket-prep/SKILL.md:35` and `:50`; c0043's Rules and mutants table (three `reasoned` rows)
Evidence: The skills disagree about what `reasoned` means:
- Ticket-prep step 3: "`checked` is `run` if prep's mutation check ran it, else `reasoned`". That allows a partly run table.
- Ticket-prep step 4: "when you prototype …, apply each row's mutant … With no prototype, mark every row `reasoned`". That reads as all rows or none.
- Review item 0: "`reasoned` rows had no prototype, so judge them by reading, or spot-check them with a scratch copy."

c0043, the pilot of this format, had a prototype (E2), yet it marks three rows `reasoned`, for example "design mode item 0 comes before item 1". So a reviewer following item 0 would wrongly conclude there was no prototype to run those rows against. The phrase "spot-check them with a scratch copy" also doesn't say what to copy when no prototype exists.
Critique: `reasoned` is what tells the reviewer where to spend effort, so the skills need to agree on it. The tempting fix is to delete "had no prototype" from item 0.
Consequences: That leaves a real case open: a prototype exists but some mutants weren't run, usually because they're costly or trivial. Should those rows be `reasoned`, and must the author say why? If yes, the reviewer knows a prototype exists and can spot-run those rows cheaply. This doesn't touch AC3 (`reasoned` stays in `## Design mode`) or AC4 (`## 4.` isn't checked).
Recommendation: Make one rule, stated in ticket-prep step 4 and mirrored in item 0: "`reasoned` means the mutant wasn't run. That is either because there's no prototype, or because a prototype exists and the row was skipped, with the reason noted in Unknowns & experiments. The reviewer reads `reasoned` rows, and when a prototype exists, spot-runs the doubtful ones on it." Drop "had no prototype" and "with a scratch copy" from item 0. Record this under "Addressed during execution" as a local adjustment.

### F3 [low] c0043's Design, Touched modules and Affected specs still describe the pre-review state
Where: `tracker/issues/active/c0043/c0043-review-second-order.md`: Design, the review skill section's item 0 bullets; `### Touched modules`; `### Affected specs`
Evidence: The Design says item 0 means "Rows marked `run` were mutation-tested in prep. Spot-run only the `reasoned` rows you doubt". The shipped skill now says to spot-run doubtful `run` rows and to read `reasoned` ones. Touched modules lists four files. It leaves out `tests/tooling/metrics-rounds.spec.luau`, `.claude/skills/metrics/SKILL.md` and `.claude/skills/tracker/SKILL.md`, although the template says the list must include "this issue's spec paths" and is "used for spend attribution". Affected specs says "New specs: the three acceptance specs", but there are five acceptance specs plus one own spec. The Verification log records these as deviations, so nothing is hidden. But the document that moves to `done/` contradicts the skill it describes.
Critique: Once done, the issue doc is the record a future author reads to learn why item 0 says what it does. The tempting fix is to leave it, since the log mentions the changes.
Consequences: Editing the Design section is allowed, because only `check.sh` and `acceptance/` are sequestered. Attribution here was `focus`, so the missing Touched modules paths didn't change this raft's spend. They would matter for a non-focused commit.
Recommendation: Update the item 0 bullets in the Design to the shipped wording (after F2's fix, if made). Add the three missing paths to Touched modules. Change Affected specs to "five acceptance specs and one own spec (`tests/tooling/metrics-rounds.spec.luau`)". No spec cases are needed.

Verdict: approve

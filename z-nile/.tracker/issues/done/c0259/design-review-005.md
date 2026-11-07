# Review 005: c0259 (design mode)
Inputs: prep worktree `prep-znile-readme-vision` at 6fd403b3 plus the uncommitted c0259.md, check.sh, acceptance/readme.spec.luau, experiments/README.draft.md, design-review-001 to 004, design-refute-001 to 004, harvest.md, z-design/lessons/status-labels-need-a-tracker-fact.md; tracker state of c0115, c0117, c0118, c0121, c0142, c0248 to c0254, c0258 (`./zn find` + `design:`).
Dropped from review-004: F1 (fixed: `LABELS` is `sub-section|id`, `ROWS` is ids, `truth()` reads the state from the README and compares it with `real()`; verified below), F2 (fixed: the legend, draft line 2, says "its own roadmap row and every label that names it").

Evidence harness: the draft copied over `z-nile/README.md`, `./zn check c0259`, then `git checkout z-nile/README.md` (`git status --short z-nile/README.md` empty): `---- 8/8 criteria passed`. Then a scratch copy of check.sh's functions (`ROOT=` to before `removed()`) with `README` pointed at scratch files and `real()` overridable per id, each run through `./zn run --time 60`:

| README | tracker | truth() |
|---|---|---|
| draft | today | PASS |
| draft | c0117 = exists (lags) | FAIL |
| draft, c0117's row and four labels `exists` (follows) | c0117 = exists | PASS |
| same (runs ahead) | today | FAIL |
| draft, c0249's row and label `designed` (follows) | c0249 = designed | PASS |
| draft | c0249 = designed (lags) | FAIL |
| c0249 row `exists` / `*exists* (c0252)` in Autonomous delivery (ahead) | today | FAIL / FAIL |
| Order's label moved into Claiming across hosts (move) | today | FAIL |
| Trust `(c0117)` → `(c0118)`, both designed (re-id label) | today | FAIL |
| roadmap `c0252` → `c0253` (re-id row) | today | FAIL |
| id-less claim label `*designed*` | today | FAIL |
| `Merging *exists* (c0252).` added to the Roadmap prose (draft:83) | today | **PASS** |
| `The worker loop *exists* (c0253).` added to the legend paragraph (draft:2) | today | **PASS** |

Round 4's fix holds in both directions. The last two rows are F1.

### F1 [medium] AC7 judges only labels inside `###` sub-sections other than Roadmap, so a labelled over-claim in the section's opening paragraph, the diagram or the Roadmap prose passes check.sh
Where: check.sh `truth()`, `[[ -n $title && $title != Roadmap ]] || continue`; c0259.md AC7 ("every issue-labelled sentence"), E3 ("An unlabelled sentence added inside a section is not caught")
Evidence: the last two rows of the table above: `Merging *exists* (c0252).` under `### Roadmap` and `The worker loop *exists* (c0253).` before the legend both pass `truth()`; AC2 (the words are defined states), AC1, AC3 and AC8 (inside the section) pass them too, so `./zn check c0259` passes a README that says two captured features exist. E3 records the gap for unlabelled sentences only; a labelled one is what AC7 claims to judge.
Critique: medium, not high, because step 1 hands the executor the exact text and step 4 makes the code reviewer diff the delivered section against the draft, which catches any added sentence; but AC7's own wording overstates what it checks, and this is the fourth round to find a place the label scan misses (round 3: parsed ids; round 4: pinned states; now: scanned scope). The tempting fix is to drop the Roadmap exclusion only.
Consequences: scanning the whole section makes the legend line (draft:2) yield `*captured*` and `*exists*` with no id, which `truth()` would hold to `exists` and fail on `*captured*`; exempting the legend line by pattern opens it as the next hiding place.
Recommendation: scan every line from `## How it should work` to `## The five parts` except roadmap table rows (`^| ` under Roadmap, already judged by `ROWS`), recording intro and diagram lines under a title such as `(intro)` and Roadmap prose under `Roadmap`; exempt the legend by pinning its whole line verbatim in check.sh (`grep -qxF` of the reviewed text: it does not depend on the tracker) and skipping exactly that line. `LABELS` gains nothing for the draft (no labels there today). Record in E3: the two mutants above fail, a label appended to the legend fails, the draft and the c0117 follow case still pass. Reword E3's limit to "an unlabelled sentence".
Lesson: z-design/status-labels-need-a-tracker-fact

### F2 [low] The lesson's "How to apply" has a run-on that drops a clause boundary
Where: z-nile/skills/z-design/lessons/status-labels-need-a-tracker-fact.md, How to apply
Evidence: "pin which issue each label belongs to by its position in the reviewed text (an ordered list in check.sh) pin only what the executor may not change, read the state words ..." reads as two edits merged.
Recommendation: "... (an ordered list in check.sh), pinning only what the executor may not change; read the state words from the delivered file ...", and add the F1 question to its `check:` ("does a label anywhere in the section, not only in its sub-sections, get judged?").

Candidate lesson (for the lead; extends z-design/status-labels-need-a-tracker-fact): a check that judges "every labelled sentence" must scan the whole region the labels may appear in, and exempt only text it pins verbatim, because c0259's AC7 skipped the opening paragraph and the Roadmap prose; check: if a labelled claim is added in a part of the section that holds no labels today, does the check see it?

Note on the verdict: the skill approves only with no high or medium finding left; this round's brief said to approve when none is high. F1 is medium, and its fix is a few lines of check.sh, so the lead should fix it (or answer it in design-refute-005) before the prep lands.

Verdict: approve

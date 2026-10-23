# Review 006: R0030 (design mode)
Inputs: worktree `prep-suite-split` at 8abff4c (`R0030.md`, its `check.sh`; c0083's document, `check.sh`, `acceptance/suites.spec.luau`, `experiments/classify.luau`, `mutate.py`, `mutants.log`); design-review-001…005 and design-refute-001…005; the review, testing, tracker, ticket-prep and architecture skills; `tracker/game-design.md`, `tracker/architecture.md`. In the worktree, `scripts/tracker.sh check c0083` fails 0/9 for the right reasons: AC1–AC6 on the missing `@scripts/lib/suites`, AC7–AC9 on the skills, greps and the five RC0 lines that execution has not edited yet. `promote-check R0030` fails only on the missing `@scripts/lib/suites` require (`tests/meta/architecture.spec.luau :: every require resolves`). I spot-ran the prototype in a private `--no-hardlinks` copy (origin remote removed, `origin/main` set to c304408, non-fixture identity): `bash tracker/issues/c0083/check.sh` passes 9/9. I applied mutants to the copy and reverted them. No tripwire fired. The worktree is unchanged apart from this file.

Dropped from review-005: F1 (option B, the user's decision, is applied. A done `check.sh` selects c0034, c0063, c0103 and `repo-fence`, and an `acceptance/` spec selects c0044, on the prototype and in the AC2 case. F1 below is a new hole at the edge of the same carve-out.)

### F1 [medium] The plain-rule exception is keyed on `acceptance/`, but c0044 and c0006 walk every `*.spec.luau` under `tracker/`, so a spec anywhere else in an item folder skips both
Where: c0083 Design, `textAffected` → "Tracker item documents" ("An item document is any file under … except the item's `check.sh` and anything under its `acceptance/` … c0044 `guard` for acceptance specs"); the testing skill's Suites paragraph text in the Design; prototype `itemFolder` (`not string.find(path, "/acceptance/", 1, true)`); Rules row "an item's check.sh and acceptance specs keep the plain rule, so their walkers run"
Evidence:
- What the walkers read. `tests/acceptance/c0044/guard.spec.luau` calls `specs("tracker", files)`, and `tests/acceptance/c0006/clone.spec.luau` calls `specs(`{root}/tracker`, files)`. Both recurse and keep every file that matches `%.spec%.luau$`. Neither looks for an `acceptance/` folder.
- Such files already exist. The tree holds item-folder specs outside `acceptance/`: `tracker/issues/done/c0053/replacements/c0005-worktree.spec.luau` and `c0015-workflow.spec.luau`. c0053's `check.sh` checks those prepared replacements.
- On the prototype copy, I wrote `tracker/issues/c0083/replacements/x.spec.luau` (in an existing item folder, so the audit stays clean). Its text names `tracker/issues/c0083/c0083-legacy-name.md` and runs `{ "clone", "-q", root, dir }`:
  - `lune run scripts/affected --` on that path prints only `tests/acceptance/c0082/real-tree.spec.luau`, and that one spec passes (1 passed, 0 failed). The Stop hook, RC0, `land` and `done` would therefore all pass.
  - Running the two walkers directly fails both: `FAIL c0006/clone.spec.luau :: no spec clones the repository with a plain git clone` and `FAIL c0044/guard.spec.luau :: no spec under tests/ or tracker/ names a <ID>-<slug>.md document`.
  - The same path under `acceptance/` selects 60 specs, both walkers included.
  - `--deps` of the existing `tracker/issues/done/c0053/replacements/c0015-workflow.spec.luau`, or of `tracker/issues/c0099/experiments/x.spec.luau`, prints only `real-tree`.
- The Design's justification is not accurate. It says c0044 guards "acceptance specs" and does not name c0006 at all. The AC2 case only tries `acceptance/x.spec.luau`, so it can't see this.
Critique:
- **Wrong selection.** The selector skips specs that its own justification says it keeps. The trigger is narrow: a spec file in an item folder outside `acceptance/`. But the tree already has two such files, and "prepared replacements" is a pattern the project has used before.
- **The backstop is weaker than it looks.** CI's `--full` would catch it on a PR. A direct push (`land`, a tracker publish) is never seen by CI, so the next unrelated PR would see it as red on `origin/main`.
- **This is the fourth hole in a row in how tracker item paths are text-selected** (review-004 F1 and F2, review-005 F1, this one). The skill says to question the mechanism. Each time, the mechanism was defined as "everything in the item folder except an enumerated set". Each hole has been a kind of file that a real-tree walker reads and that the enumeration missed.
- **The tempting fix** is to add `replacements/` to the exception. That is the same enumeration, one entry longer, and the next walker with a different filter repeats it.
Consequences:
- **Option 1: carve out by file kind.** Define the plain-rule exception by what the walkers filter on, not by folder name: any `check.sh` and any `*.spec.luau` anywhere in an item folder. That is exactly the filters of c0034, c0063, c0103, `repo-fence`, c0044 and c0006 today. A future walker with a new filter, such as `*.luau` under `experiments/`, would still need a rule.
- **Option 2: define the narrow set positively.** Narrow only Markdown in an item folder, `*.md` at any depth: `spend.md`, reviews, refutes, issue and raft documents. This is the decision's own parenthetical, "documents, `spend.md`, reviews". Everything else keeps the plain rule. It removes the enumeration, and a new kind of file is plain by default, which is the safe direction.
  - Cost: experiments and replacements then select about 60 specs. They are written in prep, and prep already pays that cost for its new `check.sh` (Scalability). So the saving on spend, review and Verification-log commits is unchanged.
  - The one listed reader stays: `real-tree` reads item `.md` files without naming them, and no other kind of reader needs a list.
- **The user's decision.** The decision says "the other files … (documents, `spend.md`, reviews)", and refute-005's option B also listed experiments among them. Option 2 reads the parenthetical as the scope. Record that reading in R0030's Theme. If the author reads "other files" as binding for experiments, choose option 1 and say so; that needs no new user decision either.
Recommendation:
- Adopt option 2. An item document is a `*.md` file under `^tracker/(issues|rafts)/(active/|done/)?[fdcR]NNNN/`. Every other file there keeps the plain rule.
- Correct the Design sentence: c0044 and c0006 walk every `*.spec.luau` under `tracker/`, and `repo-fence`, c0034, c0063 and c0103 read `check.sh` files.
- Update the testing skill's Suites paragraph text: "An item document (a `.md` file in …)". AC7's tokens are unchanged.
- In the AC2 case, add two paths that must select both `tests/acceptance/c0044/guard.spec.luau` and `tests/acceptance/c0006/clone.spec.luau`: `tracker/issues/c9999/replacements/x.spec.luau`, and `tracker/issues/done/c9999/experiments/x.spec.luau` under `done/`. Also add `tracker/issues/c9999/experiments/x.luau`, which must not be narrowed. A token above the item folder still selects for it, so assert that `tests/tooling/repo-fence.spec.luau` or another `tracker`-token spec is selected.
- Add Rules rows with these mutants, each killed on the prototype: "a spec outside `acceptance/` under the narrow rule" and "a non-Markdown file under the narrow rule".
- Re-measure E2's item rows and Scalability. The commit-shaped 73 and the one-document 1 should not move.

### F2 [medium] The item-document case asserts the narrow rule and the reader trigger only on a combined change, so two plausible mutants survive
Where: `suites.spec.luau`, case "a tracker item's documents select only the specs that name them, plus the real-tree audit", lines 261–296; Rules rows "an item document matches only itself or a folder at or below its item folder, for issues and rafts, backlog, active and done" and "the real-tree audit runs for any change under tracker/issues or tracker/rafts"; `experiments/mutate.py` P5–P8
Evidence: I ran both mutants on the prototype copy, then reverted them.
- **Mutant A.** The narrow rule skips the issue backlog and done rafts (`root = nil` when `kind == "issues" and life == ""`, or `kind == "rafts" and life == "done/"`). `suites.spec.luau` still passes, 16 passed and 0 failed. Meanwhile `scripts/affected -- tracker/issues/c9999/c9999.md` selects 60 specs, not 1, and `tracker/rafts/done/R9999/spend.md` selects 61.
  - The "nothing else" loop covers only the four cells in `docs`: rafts/active, issues/active, issues/done and the rafts backlog.
  - The lone-document check (`c9999.md`) asserts only that `real-tree` is in and pellets is out. Sixty harness specs pass both of those checks.
  - P6, P7 and P8 remove a whole kind or a whole lifecycle stage at once, which is why they were killed while this per-cell mutant is not.
- **Mutant B.** The reader trigger fires only for `^tracker/issues/`. The spec still passes 16/0, and `scripts/affected -- tracker/rafts/active/R0034/spend.md` prints nothing.
  - Every case that asserts `real-tree` also has an issue path in its change list.
  - P5 changed the trigger to `/check%.sh$`, a different mutant.
  - Under B, a commit that touches only a raft's spend or review runs no spec at all, and the real-tree audit that covers raft folders is skipped.
Critique:
- The issue backlog is the capture path: `make-issue` writes the document, and `land` runs the gate on it. That is the commonest item-document change after spend rows.
- Under mutant A, every capture gates on 60 harness specs (about 58 s) and every check stays green. The 1-spec saving that the Scalability and Usability sections promise is unpinned for exactly that path.
- The tempting fix is one more `docs` entry. That pins one more cell, but the lone-document assertion stays too weak to catch over-selection.
Consequences: an exact assertion on a single document holds for every cell at once. It depends on no other spec naming a `tracker/issues/c9999/…` path, which is true (`c9999` appears in no spec), and the assertion message should say to pick another id if one ever does. This adds no new rule.
Recommendation:
- Replace the lone-document check with a loop over all six cells: `tracker/issues/c9999/c9999.md`, `tracker/issues/active/c9999/c9999.md`, `tracker/issues/done/c9999/c9999.md`, `tracker/rafts/R9999/spend.md`, `tracker/rafts/active/R9999/review-001.md` and `tracker/rafts/done/R9999/spend.md`. Each one alone must select exactly `{ "tests/acceptance/c0082/real-tree.spec.luau" }`. That kills mutant A, and the raft-only paths kill mutant B.
- Add both mutants to the item rows of the Rules table, run on the prototype, and record them in E4 and `mutants.log`.

Verdict: changes

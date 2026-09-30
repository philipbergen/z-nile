# Review 001: R0070 (design mode)
Inputs: main at 2dcee74 plus the uncommitted prep: `tracker/rafts/R0070/{R0070-review-second-order.md,check.sh}`, `tracker/issues/c0410/{c0410-review-second-order.md,check.sh,acceptance/*.spec.luau}`; `.claude/skills/{review,ticket-prep,tracker,testing,execute-raft}/SKILL.md`; `tracker/templates/issue/doc.md`; `scripts/tracker/main.luau` (`reviewProblem`, `cmd.metrics`); `scripts/tracker/{store,spend}.luau`; the review files present under `tracker/rafts/**` and `tracker/issues/**`.
Prototype: a scratch worktree (since removed) with a deliberately wrong review-skill edit, described in F1. This review is written in the proposed second-order format, as the pilot asks.

### F1 [high] AC3 (and AC4) phrase checks pass a wrong implementation: "one step further" is already in the template line, and nothing checks which section a phrase is in
Where: `tracker/issues/c0410/check.sh` AC3 and AC4 (`has_all` greps the whole file); c0410 Design, review-skill bullets 1–3; the Rules and mutants rows "check.sh AC3 | either text missing" and "check.sh AC4 | either text missing".
Evidence: The Design's own `Consequences:` template line reads `<take that fix one step further: …>`, so the phrase AC3 relies on for "the paragraph after the severity list" is satisfied by the template alone. I prototyped this wrong edit of the review skill:
- the template gets `Critique: <why it matters>`, `Consequences: <take that fix one step further: new rules, or "none">` and `Recommendation: <the smallest change that resolves it>` (the old Fix text, renamed);
- no paragraph after the severity list;
- the audit item is added as `0. **Rules and mutants**: audit the table; a missing row is a finding.` under **Code mode**, not Design mode.

`bash tracker/issues/c0410/check.sh` gave `PASS AC1` and `PASS AC3`. So the core behaviour change (a written rule to trace fixes forward, and a Recommendation that covers them) can be missing, with the audit in the wrong mode, and AC1 and AC3 still pass. AC4 is the same shape: `Rules and mutants`, `consequence step` and `consequences:` in any one sentence anywhere in ticket-prep passes, including one that isn't in step 3 or step 5.
Critique: For a docs-only chore the phrase checks are the whole acceptance, and the table claims they kill "either text missing". The obvious fix is a different phrase for the paragraph (for example `isn't finished at`) and leaving it at that. That closes this one hole, but leaves the section problem: design-mode text can still sit in code mode, and ticket-prep text can sit in any step.
Consequences: Checking by section means the spec has to name section anchors, and those become pinned in a promoted, never-edit acceptance spec. Renaming a skill heading later (for example `## 5. Adversarial design review (required)`) would turn main red and need a chore. Exact full-heading matches make that brittle. Matching on a heading prefix is sturdier. Also, "a first item" in Design mode is ambiguous: either it's numbered `0.`, or items 1–8 are renumbered. The spec must accept whichever one the Design picks, and the Design has to pick. Nothing outside the skill refers to these items by number: I grepped the other skills and found no "design-mode point N". So either choice is safe, but the executor shouldn't have to guess.
Recommendation: Replace the AC3/AC4 greps with a small acceptance spec (`skills.spec.luau`) that slices sections by heading prefix and asserts:
- (a) review skill, text **outside** the ```` ```markdown ```` block contains `one step further`, so the template line alone doesn't count;
- (b) the section from `\n## Design mode` to the next `\n## ` contains `Rules and mutants` and `missing row`, and its first numbered item is the audit. State in the Design that it is item `0.`, so items 1–8 keep their numbers;
- (c) the section from `\n## Code mode` to the next `\n## ` does **not** contain `Rules and mutants`, as the Design says;
- (d) the template's `Recommendation:` line no longer contains `smallest change`, or positively contains `consequences`;
- (e) ticket-prep: the `\n## 3.` section contains `Rules and mutants`, and the `\n## 5.` section contains `consequence step` and `consequences:`.

Add one table row per assertion, with the prototype above as the mutant for (a) to (d), and a mutant that puts the bullet in step 5 instead of step 3 for (e).

### F2 [medium] The rounds metric can't tell before-rafts from after-rafts, and the baseline in the Problem is wrong for R0040
Where: c0410 Problem ("R0040 and R0060 each needed four, and R0050 four as well"); Design → Maintainability ("compare design rounds for rafts prepped after this merges"); `cmd.metrics` table spec.
Evidence: `tracker/rafts/done/R0040` holds `design-review-001.md` … `design-review-005.md`, so the new table will print `| R0040 | 5 | 2 |`, not the 4 the Problem states. The table has no field that says which rafts used the new format. Raft ids don't encode prep time either: R0020 (1 design review) and R0060 (4) are both backlog rafts prepped before this change, and a raft created before the merge can be prepped after it. The user's explicit instruction is "measure whether rounds drop first". As designed, answering that means someone reconstructing merge dates by hand.
Critique: The measurement is the stated gate for the deferred ideas (Non-goals, Risks). If it's ambiguous, the go/no-go decision on parallel reviewers rests on a guess. The tempting fix is to correct the "four" in the Problem and add a note: "rafts after R0070 are the new format".
Consequences: An id cutoff is wrong for any raft created before the merge but prepped after it, and for R0070 itself, whose round 1 (this file) already uses the new format. A self-classifying column is more robust, but it brings a detection rule (what makes a raft "second-order"?), a value for rafts with no reviews, and a stable spec case for each value. There are two stable positive cases: R0070's `design-review-001.md` (this file, never edited after commit) and any done raft for classic.
Recommendation: Fix the baseline sentence: R0040 5, R0050 4, R0060 4, R0010 3, R0030 3. Add a `format` column, classified from the raft's `design-review-001.md`:
- `second-order` if the file contains a line starting `Consequences:`;
- `classic` if the file exists without such a line;
- `-` if there's no design review.

Spec cases: R0010 is `classic`, R0070 is `second-order` (R0070 is active while the spec runs in `check.sh`, and done afterwards, with the same file). Add a table row whose mutant hard-codes `classic`.

### F3 [medium] Design-mode item "every row's spec case must … fail for its mutant" makes each round of review a mutation run, against the user's "cheaply"
Where: c0410 Design, review skill, third bullet ("every row's spec case must exist and fail for its mutant"); raft Risks ("one line per finding").
Evidence: As worded, a reviewer can only confirm "fails for its mutant" by planting each mutant and running the spec: a scratch worktree, a `lune` run per row, every round. That's what E2 did in prep, at prep cost. The Risks section prices the change at "one line per finding" and ignores this. c0410's own table has 8 rows, but E2 says "all six mutants fail". So even the author's record doesn't show which rows were actually run. Nothing says whether a row's result was run or reasoned, so the reviewer can't trust the table and would have to rerun it.
Critique: This drives cost straight up. It can also make reviewers either skip the check silently or spend most of a round on it. The tempting fix is to drop "and fail for its mutant" from the audit.
Consequences: Dropping it makes the table an unverified claim, and F1 shows that's exactly where holes hide: a row claiming a mutant it can't kill. Keeping verification means someone has to record which mutants were actually run. That adds a small piece of state to the table: a column, or a marker in the mutant cell. It also means the template and ticket-prep need to say how to write it.
Recommendation: In the template and ticket-prep, the mutant cell ends `(run)` or `(reasoned)`. Prep fills `(run)` from the mutation check. The review skill's item says: check that each `(reasoned)` row's case can tell the mutant apart by reading its assertion, and spot-run at most one or two doubtful rows. A missing row or an unkillable mutant is still a finding. Reconcile c0410's own E2 count with its table (8 rows, and say which were run). Pin the marker with a case in `table.spec` (the template's comment or header mentions `(run)`), with a table row for it.

### F4 [low] Rules and mutants audit of c0410: rows missing for the metrics placement and the issue-directory exclusion
Where: c0410 Rules and mutants table; Design → `tracker.sh metrics` bullets.
Evidence: Two stated rules have no row and no case:
- "After the per-type table, and before the rework lines": a mutant that prints the table last passes, because `rounds.spec` scans every line after the header.
- "Issue directories aren't counted": a mutant that adds member issues' review files passes, because no done issue has any. The `review-NNN.md` files under raftless `c0350` and `c0331` aren't reachable per raft either.

Also, the rows for AC3/AC4 claim mutants their checks can't kill (see F1).
Critique: These are low-impact. The table is the artefact this raft asks reviewers to audit, though, and its own table should hold up to that audit. The tempting fix is to add both rows with new spec cases.
Consequences: A placement case pins output order in a promoted spec, so a future metrics section inserted between the tables would break it. The issue-dir exclusion has no stable positive case in the repo today: it would need a fixture, or a raftless issue with review files, which `store.all("raft")` never visits anyway.
Recommendation: Add a placement case to `rounds.spec` (the header appears after `| type | issues |` and before `Rework =`), with a row. For the issue-directory rule, add a row that marks it `(reasoned)` (see F3) with no case, because the per-raft iteration makes it structurally true. Don't build a fixture.

### F5 [low] Code-mode findings get Recommendations, but the executor's answer loop and refute format are unchanged
Where: c0410 Design ("Code mode uses the same finding format"); `.claude/skills/execute-raft/SKILL.md` Phase 4 step 4 (`- F3: fixed <short sha>: <what changed>`); raft Whole-raft design ("No change to … other skills").
Evidence: Code reviewers will write `Consequences:`/`Recommendation:`, but execute-raft doesn't ask the executor to run the consequence step or record it. Design refutes become `fixed: <what>; consequences: …`, while code refutes stay `fixed <sha>: <what>`. The Recommendation also invites "user decisions", but code mode runs autonomously and the acceptance specs are sequestered, so a Recommendation to change a spec can't be followed.
Critique: The raft is aimed at design rounds, so this is scope clarity, not a defect. The tempting fix is to extend execute-raft too.
Consequences: Editing execute-raft grows the raft, adds phrase checks, and changes a skill the Design explicitly fences off. It also touches the `refuted: below the merge threshold` interim form and the c0360 `deferred` plans.
Recommendation: Keep execute-raft unchanged. Add one sentence to the review skill's code-mode section: in code mode, a Recommendation must not require changing sequestered `check.sh` or acceptance files or asking the user; name the escalation instead. State in c0410 Non-goals that code-mode answers keep their current format.

Verdict: changes

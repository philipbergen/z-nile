---
name: ticket-prep
description: Turn backlog issues into an execution-ready raft - group by functional adjacency (single type), design the raft as a whole and each issue in detail, write check.sh files and acceptance specs, run cheap experiments, and pass an adversarial design review. Use for "prep", "make a raft", "design these issues".
---

# Ticket prep (includes make-raft)

The goal is a raft that **any strong agent can deliver on the first attempt without asking questions.** Time spent here is cheaper than rework. Be thorough.

## 1. Form the raft
- **Candidates**: `scripts/tracker.sh list backlog`. Group issues by **functional adjacency**: they touch the same features or interfaces, or they're only meaningful together.
- **One type per raft.** Never mix feature, defect and chore. A defect found while planning a feature raft goes in its own raft.
- **Size**: aim for something that fits in one reviewable PR, roughly under 1,500 changed lines. Split larger groups into sequential rafts.
- **Create it**: `scripts/tracker.sh new raft <feature|defect|chore> <slug> <ids…>`. A single issue gets a raft too: add `--single`.
- If an issue is missing, create it first with the `make-issue` skill.

## 2. Design the raft as a whole
In `R…-slug.md`, before any issue gets detail:
- **Theme**: why these belong together.
- **Whole-raft design**: the module map, which features are new or changed, the interfaces between issues (typed signatures), and the data flow. Add a small diagram if it helps.
- **Architecture changes**: any new dependency edge goes in `tracker/architecture.md` now, including the ```` ```deps ```` block.
- **Order & dependencies**, **Risks & rollback**.

## 3. Design each issue in detail
Fill every section of the issue template. Requirements:
- **Design**: concrete paths, public types and function signatures, the pure/adapter split, and server authority. Scalability, Maintainability and Usability are answered specifically (see the architecture checklist), not with platitudes.
- **Touched modules**: one backticked path per bullet. Then run `lune run scripts/affected -- <paths>` and paste its output, plus the new specs, into **Affected specs**.
- **Unknowns & experiments**: list every assumption you can't *prove* from the repo or from docs you've read.
  - Each gets a pass/fail question, a method and a fallback.
  - **Run the cheap ones now** (Lune spikes, `rojo build` probes, doc checks) and record the results. What's left becomes the executor's Phase 1.
- **Regression guard**: name the existing specs and behaviors at risk, and add regression specs to the Test plan.
- **Test plan**: `spec file :: case → ACn`.
- **Acceptance criteria**:
  - **Checked**: nearly all criteria.
  - **Judged**: only with a rubric.
  - **Observed**: minimal Studio steps.
  Push hard to turn Judged and Observed criteria into measurable proxies (see the testing skill).
- **Implementation steps**: small, ordered, and each one verifiable.

## 4. Write the executable acceptance
- **Issue checks**: `check.sh` for each issue, with one `check "ACn: …"` per Checked criterion.
- **Raft checks**: the raft's `check.sh` gets RCn end-to-end checks after the generated RC0 lines.
- **Write the acceptance specs now** in `tracker/issues/<id>/acceptance/`, as real spec files with the cases that pin the behavior. Require only through aliases, and see the testing skill for where these live.
  - They fail, because the code doesn't exist yet. Main stays green because the gate doesn't run them.
  - This is what makes the checks unfakeable and sequestered.
- **Verify the wiring**: `scripts/tracker.sh check <id>` runs and fails *for the right reasons*: assertion failures or missing modules, not bash errors.

## 5. Adversarial design review (required)
1. Mark the items `design: reviewed` once the author considers them complete. Use `tracker` frontmatter edits.
2. Start a **clean** reviewer, with none of your context: a fresh subagent, given the `review` skill (design mode), the raft and issue paths, and read access to the repo. It writes `design-review-NNN.md` in the raft directory.
3. Answer every finding:
   - Fix it in the documents, specs or `check.sh`.
   - Or rebut it in `design-refute-NNN.md` (`- F2: refuted: <evidence>` or `- F2: fixed: <what>`).
4. Run another round with a new clean reviewer if any high finding was fixed or the design changed materially. Stop after 3 rounds and bring the open questions to the user.
5. When the latest round has `Verdict: approve`, or only low findings remain and all are answered, set `design: ready` on the raft and every member.

## 6. Commit and hand off
- **Commit** the prepared tracker items, acceptance specs and architecture changes to main as one commit, `tracker: prep R0010 <title>`, then push.
  - Ask the user before committing if they haven't approved prep work going straight to main.
- **Report**:
  - the raft ID and its issues;
  - the key design decisions;
  - experiment results;
  - review rounds, and what changed because of them;
  - anything left for Observed.
- **Next step**: `/make-prompt R0010`.

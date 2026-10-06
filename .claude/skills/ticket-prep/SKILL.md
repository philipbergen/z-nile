---
name: ticket-prep
description: Turn backlog issues into an execution-ready raft - group by functional adjacency (single type), design the raft as a whole and each issue in detail, write check.sh files and acceptance specs, run cheap experiments, and pass an adversarial design review. Use for "prep", "make a raft", "design these issues".
---

# Ticket prep (includes make-raft)

The goal is a raft that **any strong agent can deliver on the first attempt without asking questions.** Time spent here is cheaper than rework. Be thorough.

## 1. Form the raft
**Work in a prep worktree** for the whole prep (new raft, design, specs, reviews): `cd "$(scripts/tracker.sh worktree prep-<slug>)"`, named by the raft's slug because its id isn't known yet (tracker skill, Worktrees). Design reviews run there too, and their files ride in the prep PR.

- **Sync first**: `scripts/tracker.sh sync` (tracker skill, Sync and claim). **Candidates**: `scripts/tracker.sh status` (what is `new`, and what others have claimed) and `scripts/tracker.sh list backlog`. Group issues by **functional adjacency**: they touch the same features or interfaces, or they're only meaningful together.
- **One type per raft.** Never mix feature, defect and chore. A defect found while planning a feature raft goes in its own raft.
- **Size**: aim for something that fits in one reviewable PR, roughly under 1,500 changed lines. Split larger groups into sequential rafts.
- **Create it**: `scripts/tracker.sh new raft <feature|defect|chore> <slug> <ids…>`: it claims the issues (status `preparing`) on `origin/main` at once, and refuses any issue another terminal holds. To prep a raft that already exists, claim it with `scripts/tracker.sh status <R-id> preparing`; an issue added during prep is claimed first (`status <id> preparing`), a dropped one released (`status <id> new`). A single issue gets a raft too: add `--single`.
- If an issue is missing, create it first with the `make-issue` skill.

## 2. Design the raft as a whole
`tracker/game-design.md` holds the user's product decisions, and it's binding. A design that needs to change a decision stops and asks the user. The raft document **quotes the decisions it relies on** under Theme, so the execution prompt carries them.

In the raft document (`R<NNNN>.md`), before any issue gets detail:
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
- **Override check**: promoted specs in `tests/acceptance/` are never edited during execution, so find the conflicts now.
  - For each Touched path, run `lune run scripts/affected -- <path>` and `grep -rlF -e <path> tests/acceptance`, and read every spec either lists. The selector alone misses specs that read a file as text; neither sees a spec that builds paths or walks a directory, so also skim the `tests/acceptance` folder names for the area. Output `ALL` carries no list (any `scripts/` or config path): use the grep alone for that path, and repeat it with the file's basename.
  - For each promoted spec S whose pinned behavior the issue deliberately changes, name S on an `Overrides:` line in **Regression guard**.
    - A chore changes S in its own raft.
    - Any other type: file a chore c that only has to remove or narrow S (prefer narrowing; if S must go, c also drops the line naming it from the owning item's `check.sh`), so `main` stays green (a spec that asserts behavior `main` doesn't have yet can't land). c names S on its own `Overrides:` line, which satisfies the check for c. The issue's Test plan gets a case that pins the new behavior, its `Overrides:` line names S and c, `depends_on: [c]` goes in its frontmatter, and its raft's **Order & dependencies** says c must be in `done/` before `start` (ready-raft refuses otherwise). A product decision behind the change goes to the user now.
  - If there is none, write `Overrides: none`.
- **Test plan**: `spec file :: case → ACn`.
- **Rules and mutants**: a table with one row per behavioural rule in the Design: `| rule | spec :: case | mutant it kills | checked |`. The mutant is a plausible wrong implementation, and the spec case must fail for it. `checked` is `run` if prep's mutation check ran it, else `reasoned`. When you prototype, fill the table from the mutation check.
- **Acceptance criteria**:
  - **Checked**: nearly all criteria.
  - **Judged**: only with a rubric.
  - **Observed**: minimal Studio steps.
  Push hard to turn Judged and Observed criteria into measurable proxies (see the testing skill).
- **Implementation steps**: small, ordered, and each one verifiable.

## 4. Write the executable acceptance
- **Issue checks**: `check.sh` for each issue, with one `check "ACn: …"` per Checked criterion.
- **Raft checks**: the raft's `check.sh` gets RCn end-to-end checks after the generated RC0 lines. A raft check finds its members with `tracker.sh find <id>` (or `members`), never a hard-coded backlog path: the directories move when the raft is readied. `tracker.sh ready` rewrites only the moved items' own literal paths in their `check.sh` files.
- **Write the acceptance specs now** in `tracker/issues/<id>/acceptance/`, as real spec files with the cases that pin the behavior. Require only through aliases, and see the testing skill for where these live.
  - They fail, because the code doesn't exist yet. Main stays green because the gate doesn't run them.
  - This is what makes the checks unfakeable and sequestered.
  - They never change the real repository: every command that changes anything runs in a fixture under `.cache/<unique name>` with its own repository, checked before each write, committing as `<name>@example.invalid` (testing skill, "Specs never touch the real repository"). Before the guards exist on your branch, or while prototyping them, run them only in a clone under `$TMPDIR`.
- **Verify the wiring**: `scripts/tracker.sh check <id>` runs and fails *for the right reasons*: assertion failures or missing modules, not bash errors.
- **Mutation check** (fills the Rules and mutants `checked` column): when you prototype the change in a scratch worktree, apply each row's mutant to the prototype and run the row's spec case, which must fail on an **assertion**, not a syntax or require error. Mark the row `run` and record the outcome in Unknowns & experiments. A row you didn't run (no prototype, or a mutant you couldn't apply) is `reasoned`: say why in Unknowns & experiments, and the reviewer then judges those rows by reading them.
- **Dry-run the promotion**: `scripts/tracker.sh promote-check <R-id>`. The only acceptable failures before implementation are requires of modules the raft will create.

## 5. Adversarial design review (required)
1. Mark the items `design: reviewed` once the author considers them complete. Use `tracker` frontmatter edits.
2. Start a **clean** reviewer, with none of your context: a fresh subagent, given the `review` skill (design mode), the raft and issue paths, and read access to the repo. It writes `design-review-NNN.md` in the raft directory. Run the reviewer on **Opus 5.5**, even if you run on a cheaper model: in Claude Code, pass `model: "opus"` to the Agent tool, and don't substitute another model, such as Fable or Sonnet.
3. Answer every finding. Before editing, run the **consequence step** on your own fix: what new rules, state, edge cases or user decisions does it bring? Add their Rules and mutants rows and spec cases in the same change, and put any decisions to the user now, all at once.
   - Fix it in the documents, specs or `check.sh`.
   - Or rebut it in `design-refute-NNN.md` (`- F2: refuted: <evidence>` or `- F2: fixed: <what>; consequences: <handled how, or none>`).
4. **Rounds: up to 5 rounds, prefer 3.** One rule decides, from the round's `design-review-NNN.md` severities and the diff of your answers:
   - After round 1 or 2, run another round with a new clean reviewer if any high finding was fixed or refuted (a new reviewer rules on a refutation) or the design changed materially.
   - After round 3 or 4, run the next round only if that round was **major**: it had a **high** finding, or answering it was more than minor.
   - Minor means the answers changed only wording, labels, comments or single assertions, and added no rule, interface, state, spec case, Rules and mutants row or public API change.
   - The **final round** is the round after which this rule runs no further round: any round 1 to 4 where it says stop, or round 5, which is always final. A final round holds a high only in round 5, and such a round goes to the user, whatever you answered to it.
5. When the final round has `Verdict: approve`, or it has no high finding and every finding in it is answered `fixed` or `refuted`, set `design: ready` (a final round with a high, which only round 5 can be, or with an unanswered finding goes to the user instead) on the raft and every member, **then run `scripts/tracker.sh status <R-id> prepared`** (carried: it edits the local documents, and refuses unless the raft and its members are `design: ready` and `preparing` on `origin/main`), and only then make the prep commit (`status` needs an origin: with `PICKMAN_PUBLISH=0` or no origin, edit the `status:` lines by hand to `prepared-<three words>` instead). Without it the members keep their `preparing` stamp and the raft can be neither started nor prompted.

## 6. Commit and hand off
- **Commit** the prepared tracker items, acceptance specs and architecture changes in the prep worktree as one commit, `tracker: prep R0010 <title>`, then follow Landing a change (tracker skill): push, PR, merge, pull the main checkout, remove the worktree.
  - Ask the user before merging prep they didn't request.
- **Report**:
  - the raft ID and its issues;
  - the key design decisions;
  - experiment results;
  - review rounds, and what changed because of them;
  - anything left for Observed.
- **Next step**: `/ready-raft R0010`.

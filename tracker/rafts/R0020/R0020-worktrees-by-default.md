---
id: R0020
type: chore
title: Worktrees by default
single: false
issues: [c0041, c0420, c0430, c0440]
design: reviewed
created: 2026-09-28
---

# R0020: Worktrees by default

## Theme
**The worktree workflow** (user decisions, 2026-09-30). Four chores that belong together because each only makes sense with the others:
- **c0041, the worktree rule**: the main checkout stays on `main` and is never edited; every change (raft execution, issue capture, ticket-prep, skill and doc edits) is made in its own git worktree, lands by pull request, is merged by the agent under the tracker skill's merge conditions, and is then pulled into the main checkout.
- **c0420, documents named `<ID>.md`**: with captures and preps running side by side in worktrees, two branches can pick the same id. With the slug in the filename that merges silently and one item vanishes; without it, git reports a conflict. The slug moves into the frontmatter.
- **c0440, worktrees inside the repo**: every job starts in a worktree directory *inside* the repo (`.worktree/R0020`, never a sibling directory), so `tracker.sh launch <target>` starts an agent there and `worktree-prune` flags strays. (c0041 sets the path convention itself: `.worktree/<R-id>` and `.worktree/<name>`.)
- **c0430, parallel workstreams**: the same worktrees let one raft be implemented by several Sonnet subagents at once (one stream per issue), each reviewed by a clean Sonnet subagent, before the whole raft is evaluated and reviewed by Opus.

## Whole-raft design
```
 c0420  documents <ID>.md, slug in frontmatter, `migrate`        (store, new, renumber, templates)
   │      └─ makes same-id collisions a git conflict
   ▼
 c0041  worktree rule: `worktree <R-id|name>` at `.worktree/…`, `worktree-prune`, guards, hooks, landing procedure, docs
   │      └─ `list` warns on a number shared by two prefixes; `store.find` errors on an id in two states
   ▼
 c0440  `tracker.sh launch <target> [-- cmd]`: jobs start in `.worktree/…`; prune flags worktrees outside it
   ▼
 c0430  parallel workstreams: `workstreams <R-id>` plan, `worktree <name> --from <ref>`, prompt section,
        execute-raft Phase 2B, review "stream mode"
```
Interfaces between the issues:
- **c0420 → c0041, c0430**: the document is `<ID>/<ID>.md`, `Item.slug` comes from the frontmatter, and `tracker.sh migrate` converts legacy documents. c0041's and c0430's specs and fixtures use the new layout.
- **c0041 → c0440, c0430**: `tracker.sh worktree <name>` (paths `.worktree/<R-id>` and `.worktree/<name>`) and the main-checkout whitelist. c0440's `launch` (in the bash wrapper) calls it; c0430 adds `--from <ref>` to the same command and its read-only `workstreams` joins the whitelist.
- All four edit `scripts/tracker/main.luau` and the tracker, execute-raft and other skills, so they're executed in this order and never in parallel (c0430's own tooling doesn't exist until it merges).

There is no new dependency edge (`tracker/architecture.md` is unchanged).

## Order & dependencies
1. **c0420** first: it renames every tracker document and updates three specs' paths. Commit `migrate` alone first; then switch the layout in **one** commit (store, templates, `new`, `renumber`, the migration itself, the three specs' paths): `tracker.sh commit` reads every document through the store, so the store change and the migration can't be committed apart (about 55 renames).
2. **c0041** (`depends_on: [c0420]`).
3. **c0440** (`depends_on: [c0041]`): `launch` and the stray warning, then the inside-the-repo wording in the docs.
4. **c0430** (`depends_on: [c0041, c0420, c0440]`).
- **Bootstrap: how R0020 itself is executed.** `tracker.sh worktree` and `launch` don't exist until this raft merges, and the prompt inlines today's execute-raft. So the human creates the worktree by hand, **detached and inside the repo directory** (the rule: every job starts in `.worktree/<…>`, never a sibling directory), and launches the agent in it. From the main checkout:
  ```
  echo '.worktree/' >> .git/info/exclude        # local ignore: .gitignore gets the entry in c0041
  git fetch origin && git worktree add --detach .worktree/R0020 origin/main
  cd .worktree/R0020 && claude
  ```
  The executor follows Phase 0 with two changes:
  - it does **not** run `git switch main && git pull` (in a linked worktree `git switch main` fails, because the main checkout has `main` checked out): it runs `scripts/check.sh --full` in the worktree, which confirms `origin/main` is green;
  - `scripts/tracker.sh start R0020` then runs today's `start`, whose `git switch -c R0020-worktrees-by-default` succeeds from a detached HEAD. (A branch created beforehand with `worktree add -b` would make `start` fail: `a branch named … already exists`.)
  The main checkout is untouched (the exclude entry is local to the clone). The raft is executed **sequentially** (Phase 2A): the parallel protocol it adds isn't available to it.
- **Transition policy (user decision, 2026-09-30): no other raft is started or active while R0020 is open, and none starts until it has merged.** Nothing is in flight today (R0060, the raft viewer, is prepped but not started). c0420 renames every tracker document, and a raft that had *moved* its items (`start`) would hit a rename/rename conflict on merging the migrated `main`; the policy avoids that instead of tooling around it. Captures and preps that only add or edit backlog documents are unaffected: they merge `main`, run `scripts/tracker.sh migrate`, and commit.
- **R0060 (c0400) was updated in place in this prep PR** so it matches the new layout (and now says it depends on R0020: `depends_on: [c0420]` on c0400, and its Order paragraph): its design line and the fixture paths in its `model`, `page` and `smoke` specs (42 paths, no assertion changed). c0420's permanent guard spec fails any later spec file that spells a literal `<ID>-<slug>.md` document path (names built by interpolation are out of its reach).
- **c0370 (duplicate id detection, backlog) is superseded** by c0041's `store.find` error and c0420's collision conflict; close it when this raft lands.
- R0070 (review second order) has merged: this prep branch already contains it, and the designs follow its rules (Rules and mutants tables, the consequence step).

## Experiments phase
Every issue was prototyped in prep (stacked: c0420, then c0041, then c0440, then c0430; all reverted, none committed) and validated together: c0420's 11 naming cases, c0041's 29 worktree cases, c0440's 7 launch cases and c0430's 13 workstream cases pass; `scripts/check.sh --full` and `promote-check R0020` pass with all three prototypes and the repo migrated (346 specs); the permanent guard spec passes once the three old specs are updated; and 13 + 19 + 15 + 19 planted mistakes (per issue's Rules and mutants table) each fail the case written for them. `workstreams R0020` on the migrated tracker prints the RC1 plan. The e2e specs also disable background git maintenance in their fixtures, after intermittent clone failures in back-to-back runs. The residual unknowns are c0041's E3 and E4 (pinned or optional), and c0430's OC1 (a real parallel run).

## Exit criteria
- **RC0**: the full gate, every member's `check.sh` and `promote-check`, as generated.
- **RC1**: the raft's own plan runs on the real, migrated tracker and orders its issues as designed: `scripts/tracker.sh workstreams R0020` lists `c0420` in wave 1, `c0041` in wave 2, `c0440` in wave 3 and `c0430` in wave 4. This ties the issues together end to end (layout, tooling, plan).

## Risks & rollback
- **Risk: process weight.** Every capture and prep now costs a PR and a CI run. Accepted by the user; the landing procedure is one documented sequence, and merging is the agent's job.
- **Memory and instructions in a nested worktree** were checked in prep (c0440 E3): a session started in `.worktree/<id>` uses the main project's memory directory, and loads the worktree's own `CLAUDE.md` and `AGENTS.md` only, so the instructions follow the branch.
- **Risk: a nested worktree inherits the main checkout's `.luaurc`** (c0440 E5). An alias that a branch renames or removes still resolves locally, to the main checkout's files, while CI, which checks out the branch alone, fails. CI is the final check, and the tracker skill says so.
- **Risk: an agent forgets the rule.** It's a documented rule, not a guard, apart from the CLI refusing `new`, `renumber` and `start` in the main checkout. Mitigation: the prompt's first action and the launch line put the agent in the worktree. A hook that denies other edits there is a candidate follow-up (c0041 Non-goals).
- **Risk: a worktree under `.worktree/` is committed from a branch created before `.gitignore` had the entry.** `worktree` branches from `origin/main`, which has the entry once this merges, and the fixtures used by the specs carry it.
- **Risk: the rename.** c0420 touches every tracker document and three specs (two of them promoted and sequestered). Mitigation: the transition policy (nothing in flight); `migrate` is idempotent and is what backlog-only branches run; JC1 requires those specs to change only in paths and fixture `slug:` lines; the old layout gives an error that names the command; the permanent guard spec catches any later literal legacy path in a spec.
- **Risk: two unmerged worktrees pick the same issue number.** With c0420 it is a `CONFLICT (add/add)` on `<ID>.md`, resolved by `renumber` before merging (tracker skill, "Conflicts"; only `add/add` means renumber); a number shared by two prefixes is only a `list` warning.
- **Risk: the parallel protocol is unproven in practice.** It can't be dogfooded until this raft merges. Mitigation: the deterministic parts (plan, `--from`, stream files) are specced; the protocol itself is ruled on by JC1 and exercised for real in c0430's OC1 (the first raft run this way); it falls back to sequential when a stream blocks or the plan says `parallel: no`.
- **Risk: Sonnet streams lower quality.** Mitigation: a clean Sonnet reviewer per stream, the lead's acceptance evaluation, and the unchanged Opus review of the sum total before `done`.
- **Rollback**: revert the PR. `migrate` is not reversible by the tooling, but a revert restores the old document names with the old code.

## Addressed during execution

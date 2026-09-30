---
name: tracker
description: Rules and CLI for the local issue/raft tracker (IDs, types, lifecycle directories, branches/PRs, spend, emergent issues). Read before creating, moving, committing or finishing any tracked work.
---

# Tracker

All work is tracked in `tracker/`, which is committed. The only way to change tracker state is `scripts/tracker.sh`. Don't move tracker directories by hand. Inside a raft, commit with `tracker.sh commit`; capture, prep and doc-only worktrees, which have no active raft, use plain `git add` and `git commit` (see Landing a change). Every change is made in a worktree (see Worktrees).

## Items
| kind | ID | example |
|---|---|---|
| feature issue | `f` + 4 digits | `f0010` |
| defect issue | `d` + 4 digits | `d0020` |
| chore issue | `c` + 4 digits | `c0030` (includes every CI/test/tooling fix, even bugs; see make-issue) |
| raft (epic) | `R` + 4 digits | `R0010` |

- **Numbering**: `f`, `d` and `c` share one number space; rafts have their own. `tracker.sh new` always picks the **next multiple of 10** above the highest number in use.
- **Legacy layout**: documents used to be named with their slug. `tracker.sh migrate` renames any such document to `<ID>.md` and adds `slug:` to its frontmatter; run it, and commit, after merging a `main` that has the new layout.
- **Conflicts**: two branches that pick the same number now conflict in git, because both write `<ID>/<ID>.md`. Only a `CONFLICT (add/add)` on that path means two items share a number: run `git merge --abort`, `git fetch origin main`, then `tracker.sh renumber <ID> <next free>` on your own branch, where next free is the next multiple of 10 above the highest number of that kind in **both** your tree and `origin/main` (`git ls-tree -d --name-only origin/main tracker/issues/ tracker/issues/active/ tracker/issues/done/`, or `tracker/rafts/…` for a raft), and merge again. `renumber` rewrites every reference. A content conflict on a document is two edits to one item: resolve it like any merge, and never renumber.
- **References**: always refer to items by bare ID, never by path. Use `tracker.sh find <id>` to get the current directory.

Each item is a directory named by its ID:
```
<ID>/<ID>.md            the document (frontmatter incl. slug + sections from tracker/templates)
<ID>/check.sh           acceptance criteria as executable checks (see the testing skill)
<ID>/acceptance/        sequestered acceptance specs (issues); `done` moves them to tests/acceptance/<ID>/
<ID>/experiments/       spikes for unknowns (issues)
<ID>/design-review-NNN.md, design-refute-NNN.md   from ticket-prep, on the raft
<ID>/review-NNN.md, refute-NNN.md                 code review, on the raft
<ID>/spend.md           written by tracker.sh commit; never edit by hand
```

## Worktrees
Every change is made in its own git worktree under `<repo>/.worktree/` and lands by pull request. The main checkout stays on `main` and is never edited. Every job runs in a worktree under `<repo>/.worktree/`, never outside the repo directory: no sibling directory next to the repo, and not the harness's own `.claude/worktrees/`.

1. **The main checkout is read-only.** The complete list of commands that may run there:
   - `git fetch`, `git pull --ff-only`, and read-only inspection (`git status|log|diff|show|worktree list`);
   - `git worktree add|remove|prune` and `git branch -D <merged branch>`;
   - `scripts/setup.sh`, once, when bootstrapping a new machine (SETUP.md);
   - the read-only tracker commands `list`, `find`, `members`, `metrics`, `workstreams`, `prompt <R-id>`, and the worktree commands `worktree`, `worktree-prune` and `launch`. (`tracker.sh check` runs an item's checks and, for a raft, the full gate, so it runs in a worktree.)
   The tracker enforces part of this: `new`, `renumber`, `migrate`, `start` and a raft-creating `prompt` refuse to run in the main checkout of a repo that has an `origin`.
2. **Every change starts with a worktree**: `cd "$(scripts/tracker.sh worktree <target>)"`.

   | work | target | path and branch |
   |---|---|---|
   | executing a raft | `R0010` | `.worktree/R0010`, branch `R0010-<slug>` |
   | capturing an issue (make-issue) | `capture-<slug>` | `.worktree/capture-<slug>`, the same branch name |
   | prepping a raft (ticket-prep) | `prep-<slug>`, the raft's slug | `.worktree/prep-<slug>`, the same branch name |
   | a skill, doc or config edit | `<area>-<slug>`, for example `skills-worktree-rule` | `.worktree/<area>-<slug>`, the same branch name |

   A change to skills, docs or tooling is still tracked work: it has an issue and normally a raft, and is executed in the raft's worktree like any other. Names are lowercase, so a prep worktree is named by the raft's slug: its id isn't known until `new raft` has run inside it. Use `tracker.sh worktree`, not the harness's own worktree feature: its directories aren't under `.worktree/`, and `worktree-prune` never sees them (it warns about any worktree outside `.worktree/` and leaves it). A worktree inside the repo also sees the main checkout's `.luaurc` as a parent configuration, so an alias a branch renames can still resolve locally: CI, which checks out the branch alone, is the final check.
3. **Launching an agent**: the human starts it *inside* the worktree with `scripts/tracker.sh launch <target>` (for example `launch R0010`; `-- <command> [args…]` runs another command than `claude`). It creates or reuses the worktree (`scripts/tracker.sh worktree`) and replaces itself with the command, so the agent gets the terminal and Ctrl-C directly. Then the hooks and every relative path already point at the right tree, and nothing depends on a `cd` persisting across tool calls (a subagent's shell resets its working directory on every call). An agent started elsewhere runs the `cd` as its first action and uses absolute worktree paths afterwards.
4. **Prep merges before execution.** A prep PR merges (Landing a change) before `make-prompt` runs, so the raft's own worktree branches from an `origin/main` that has the prepped items. `make-prompt` never creates a raft: a raftless issue goes back to ticket-prep.

## Lifecycle: the directory is the status
- **Paths**: `tracker/{issues,rafts}/<ID>` is backlog, `…/active/<ID>` is in progress, and `…/done/<ID>` is finished.
- **The design field**: frontmatter `design:` moves `draft` → `reviewed` → `ready`, and only `ticket-prep` sets it.
- **Everything worked is a raft.** A raft has exactly one type (feature, defect or chore), and every member issue must match it. A lone issue gets a `single: true` raft made by ticket-prep in its prep worktree; `tracker.sh prompt <issue>` refuses to create one in the main checkout.
- **One raft = one branch (`R0010-<slug>`) = one PR.** In Phase 2B, temporary stream branches (`ws-<issue>`) feed the raft branch and are deleted.

| step | command | effect |
|---|---|---|
| start | `tracker.sh start R0010` | clean tree required; members must be `design: ready`. Creates the branch, moves the raft and its members to `active/`, commits, pushes, and opens a **draft** PR. Do this first, so the in-progress claim is visible right away. |
| worktree | `tracker.sh worktree <R-id\|name>` | creates or reuses `<repo>/.worktree/<R-id\|name>` on its own branch from a freshly fetched `origin/main` and prints its path. A raft's worktree is `.worktree/R0010` (branch `R0010-<slug>`); any other is `.worktree/<name>`. Refuses a done raft, and a branch that is checked out elsewhere. For a named worktree, `--from <ref>` cuts the new branch from that ref instead of `origin/main` (used for workstream streams: `tracker.sh worktree ws-<issue> --from <raft branch>`). |
| workstreams | `tracker.sh workstreams <R-id>` | read-only plan for parallel execution (execute-raft Phase 2B): issues in waves from `depends_on` and overlapping Touched modules, and a last line `parallel: yes (wave k: …)` or `parallel: no` |
| launch | `tracker.sh launch <R-id\|name> [-- cmd…]` | `worktree`, then runs the command (default `claude`) in that worktree with `exec`: terminal, signals and exit status are native. Refuses an unusable command or worktree path before anything starts |
| prune | `tracker.sh worktree-prune` | removes the worktree and branch of every raft that is in `done/` on `origin/main` (any merge strategy); keeps the rest, never forces, and lists named worktrees |
| focus | `tracker.sh focus f0010` | the following commits are attributed to that issue |
| commit | `tracker.sh commit -m "msg" [--issue f0010]... [--time 25]` | `git add -A`, then records spend rows in each issue's `spend.md` and the raft's summary **in the same commit**, adds `Issue:` trailers, and pushes |
| done | `tracker.sh done R0010` | requires the latest review round to be resolved and the raft's `check.sh` to pass. Promotes acceptance specs to `tests/acceptance/`, moves everything to `done/`, commits, pushes, marks the PR **ready**, and appends spend to the PR body |

## Landing a change
One procedure for every change: a raft, a capture, a prep or an edit.
0. **Sync first.** `git fetch origin main && git merge origin/main` in the worktree.
   - If `main` brought the new document layout, run `scripts/tracker.sh migrate` and commit.
   - A `CONFLICT (add/add)` on a tracker document means two items picked the same number: see Conflicts.
   - Then run `scripts/tracker.sh list` (it fails on a duplicate id and warns when one number is shared by two prefixes; renumber yours if you can) and `scripts/check.sh --full`.
1. **Commit in the worktree**: `tracker.sh commit` inside a raft; plain `git add` and `git commit` elsewhere.
2. **Push and open the PR**: `git push -u origin <branch>`. A raft's PR is opened as a draft by `start`; any other PR is opened ready with `gh pr create`.
3. **Merge** only when the conditions under Merging hold, with `gh pr merge --squash`. A raft additionally needs `tracker.sh done` and a resolved review. Prep or capture that the user didn't ask for is not merged without asking.
4. **After the merge, one chained command, run last**: `git -C <root> pull --ff-only; git -C <root> worktree remove <path> && git -C <root> branch -D <branch>; git -C <root> worktree prune`. `<root>` is the first path in `git worktree list`. When the agent was launched inside the worktree, removing it removes the session's own directory, so nothing runs after this command: post the final report first. The alternative is to leave removal to `tracker.sh worktree-prune`, run later from the main checkout.

## Merging
The agent that delivered the change merges its own PR once the evidence is in. Don't wait for a human. Merge only when **all** of these hold:
1. **For a raft**, `tracker.sh done` succeeded: the latest review round is resolved and the raft's `check.sh` passed. The PR is ready, not draft, and has no unresolved `BLOCKED:` comment. The results of the most recent review are already on the PR as a comment (execute-raft Phase 4). Only a *significant* finding in `review-003.md` (any high, or a failed Judged criterion) blocks the merge and engages the human; mediums and lows become follow-up issues (execute-raft Phase 4 step 7).
2. `scripts/check.sh --full` passes on the final head, run by you.
3. CI is green on the PR's exact head sha. `done` pushes and then marks the PR ready, and the ready event starts the `pull_request` run. Poll `gh pr view <pr> --json headRefOid,statusCheckRollup` until `headRefOid` equals `git rev-parse HEAD` and the `gate` check is `COMPLETED` with conclusion `SUCCESS`. Any other state is **not** green: a missing `gate`, `IN_PROGRESS`, or `SKIPPED` (the run from when the PR was a draft) means keep waiting; `FAILURE` is red. If no `gate` run for this sha appears within about 5 minutes of the ready event, dispatch one with `scripts/ci-verify.sh` (it needs HEAD equal to `origin/<branch>`, so push first) and wait. If the dispatched run fails, treat it as red.
4. `gh pr view <pr> --json mergeable,mergeStateStatus` shows `MERGEABLE` and `CLEAN` (`UNKNOWN` is GitHub still computing it right after `done`: re-poll for up to a minute before deciding); any other state (`BEHIND`, `BLOCKED`, `UNSTABLE`, `DIRTY`) is not mergeable. `done` is preceded by a merge of `origin/main` (execute-raft Phase 5), so this should hold. If `main` moved since, and the merge is a clean one, merge `origin/main` in with plain `git` (`tracker.sh commit` needs an active raft, and `done` has moved it), rerun `check.sh --full`, push, and repeat step 3. If it conflicts, or it needs anything beyond renumbering colliding IDs (`renumber` per Conflicts), post `BLOCKED:` and stop: a finished PR gets no unreviewed code changes.
5. The human hasn't said to hold.

Then `gh pr merge <pr> --squash --subject "<raft>: <title> (#<pr>)" --body $'<summary>\n\n<the Co-Authored-By line from your commit instructions>'` (the `$'...'` form makes the newlines real, so the trailer is a trailer). Get the merge sha with `gh pr view <pr> --json mergeCommit -q .mergeCommit.oid`. Then follow Landing a change, step 4. This repo may have no branch protection, so these conditions are the only gate: you enforce them. Never use `--admin`, and never merge on red or missing CI, an unresolved review, or a stop condition. If any condition can't be met, leave the PR as it is, post a `BLOCKED:` comment saying which, and stop.

Observed criteria (human Studio playtests) do not block the merge. Put them in the final report and PR comment, and file any failure the human finds later as a defect issue.

## The PR is the visible record
The draft PR opened by `start` stays the live log of the raft. Every `tracker.sh commit` pushes. In addition, comment on the PR (`gh pr comment`) when: a review starts (with the sha), a review file lands (verdict and findings by severity), a review is answered (the refute lines), an issue finishes, and on any `BLOCKED:` stop. Never sit on unpushed work, and never leave review files uncommitted. See execute-raft Phase 4.

## Spend (best effort, automatic)
- **Lines**: the staged diff, excluding `tracker/`. On the `done` commit, the promoted `tests/acceptance/` specs are also excluded, because they're prep work. Later edits to them, for example a defect fix, do count.
- **Attribution**:
  1. `--issue` flags if given;
  2. otherwise the current focus;
  3. otherwise every issue in the raft.
  With several issues, each file's lines go to the issue whose **Touched modules** lists that path; files nobody claims are split evenly.
- **Minutes**:
  - `--time <minutes>` when you actually know how long you worked on it. Prefer this.
  - Otherwise the wall-clock time since the previous commit, capped at 45 minutes.
  - With several issues, minutes are split in proportion to lines added.
- **Commit often**, at least once per issue and once per review round. Smaller commits mean more accurate attribution.

## Emergent issues
- **Can't be postponed** (it blocks the raft's check.sh, or shipping without it would break something):
  1. `tracker.sh new issue d <slug> --raft R0010`. It's created directly in `active/` with `emergent: true`, using the correct type even if that differs from the raft's.
  2. Fill in Problem, Solution and ACs, plus a `check.sh`.
  3. Fix it in the same PR.
  4. List it under the raft's "Addressed during execution".
  Its spend counts toward its own type, which is how rework is measured.
- **Can be postponed**: `tracker.sh new issue <f|d|c> <slug>` into the backlog, mention it in the final report, and don't fix it now.

## Other commands
- `tracker.sh list [backlog|active|done]`
- `tracker.sh members R0010`
- `tracker.sh check <id>`
- `tracker.sh prompt <id> [--stdout]`
- `tracker.sh metrics [--include-active]`

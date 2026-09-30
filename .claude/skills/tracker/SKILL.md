---
name: tracker
description: Rules and CLI for the local issue/raft tracker (IDs, types, lifecycle directories, branches/PRs, spend, emergent issues). Read before creating, moving, committing or finishing any tracked work.
---

# Tracker

All work is tracked in `tracker/`, which is committed. The only way to change tracker state is `scripts/tracker.sh`. Don't move tracker directories by hand, and don't commit tracked work with a plain `git commit`.

## Items
| kind | ID | example |
|---|---|---|
| feature issue | `f` + 4 digits | `f0010` |
| defect issue | `d` + 4 digits | `d0020` |
| chore issue | `c` + 4 digits | `c0030` (includes every CI/test/tooling fix, even bugs; see make-issue) |
| raft (epic) | `R` + 4 digits | `R0010` |

- **Numbering**: `f`, `d` and `c` share one number space; rafts have their own. `tracker.sh new` always picks the **next multiple of 10** above the highest number in use.
- **Conflicts**: if two PRs pick the same number, whoever merges or rebases second **steps up by one** with `tracker.sh renumber f0010 f0011`, or `f0012` if that's taken too. `renumber` rewrites every reference.
- **References**: always refer to items by bare ID, never by path. Use `tracker.sh find <id>` to get the current directory.

Each item is a directory named by its ID:
```
<ID>/<ID>-<slug>.md     the document (frontmatter + sections from tracker/templates)
<ID>/check.sh           acceptance criteria as executable checks (see the testing skill)
<ID>/acceptance/        sequestered acceptance specs (issues); `done` moves them to tests/acceptance/<ID>/
<ID>/experiments/       spikes for unknowns (issues)
<ID>/design-review-NNN.md, design-refute-NNN.md   from ticket-prep, on the raft
<ID>/review-NNN.md, refute-NNN.md                 code review, on the raft
<ID>/spend.md           written by tracker.sh commit; never edit by hand
```

## Lifecycle: the directory is the status
- **Paths**: `tracker/{issues,rafts}/<ID>` is backlog, `…/active/<ID>` is in progress, and `…/done/<ID>` is finished.
- **The design field**: frontmatter `design:` moves `draft` → `reviewed` → `ready`, and only `ticket-prep` sets it.
- **Everything worked is a raft.** A raft has exactly one type (feature, defect or chore), and every member issue must match it. Running a single issue means wrapping it in a placeholder raft (`single: true`); `tracker.sh prompt <issue>` does this automatically.
- **One raft = one branch (`R0010-<slug>`) = one PR.**

| step | command | effect |
|---|---|---|
| start | `tracker.sh start R0010` | clean tree required; members must be `design: ready`. Creates the branch, moves the raft and its members to `active/`, commits, pushes, and opens a **draft** PR. Do this first, so the in-progress claim is visible right away. |
| focus | `tracker.sh focus f0010` | the following commits are attributed to that issue |
| commit | `tracker.sh commit -m "msg" [--issue f0010]... [--time 25]` | `git add -A`, then records spend rows in each issue's `spend.md` and the raft's summary **in the same commit**, adds `Issue:` trailers, and pushes |
| done | `tracker.sh done R0010` | requires the latest review round to be resolved and the raft's `check.sh` to pass. Promotes acceptance specs to `tests/acceptance/`, moves everything to `done/`, commits, pushes, marks the PR **ready**, and appends spend to the PR body |

## Merging
The agent that delivered the raft merges its own PR once the evidence is in. Don't wait for a human. Merge only when **all** of these hold:
1. `tracker.sh done` succeeded: the latest review round is resolved and the raft's `check.sh` passed. The PR is ready, not draft, and has no unresolved `BLOCKED:` comment. The results of the most recent review are already on the PR as a comment (execute-raft Phase 4). Only a *significant* finding in `review-003.md` (any high, or a failed Judged criterion) blocks the merge and engages the human; mediums and lows become follow-up issues (execute-raft Phase 4 step 7).
2. `scripts/check.sh --full` passes on the final head, run by you.
3. CI is green on the PR's exact head sha. `done` pushes and then marks the PR ready, and the ready event starts the `pull_request` run. Poll `gh pr view <pr> --json headRefOid,statusCheckRollup` until `headRefOid` equals `git rev-parse HEAD` and the `gate` check is `COMPLETED` with conclusion `SUCCESS`. Any other state is **not** green: a missing `gate`, `IN_PROGRESS`, or `SKIPPED` (the run from when the PR was a draft) means keep waiting; `FAILURE` is red. If no `gate` run for this sha appears within about 5 minutes of the ready event, dispatch one with `scripts/ci-verify.sh` (it needs HEAD equal to `origin/<branch>`, so push first) and wait. If the dispatched run fails, treat it as red.
4. `gh pr view <pr> --json mergeable,mergeStateStatus` shows `MERGEABLE` and `CLEAN` (`UNKNOWN` is GitHub still computing it right after `done`: re-poll for up to a minute before deciding); any other state (`BEHIND`, `BLOCKED`, `UNSTABLE`, `DIRTY`) is not mergeable. `done` is preceded by a merge of `origin/main` (execute-raft Phase 5), so this should hold. If `main` moved since, and the merge is a clean one, merge `origin/main` in with plain `git` (`tracker.sh commit` needs an active raft, and `done` has moved it), rerun `check.sh --full`, push, and repeat step 3. If it conflicts, or it needs anything beyond renumbering colliding IDs (`renumber` per Conflicts), post `BLOCKED:` and stop: a finished PR gets no unreviewed code changes.
5. The human hasn't said to hold.

Then `gh pr merge <pr> --squash --subject "<raft>: <title> (#<pr>)" --body $'<summary>\n\n<the Co-Authored-By line from your commit instructions>'` (the `$'...'` form makes the newlines real, so the trailer is a trailer). Get the merge sha with `gh pr view <pr> --json mergeCommit -q .mergeCommit.oid`. Then follow "After merge". This repo may have no branch protection, so these conditions are the only gate: you enforce them. Never use `--admin`, and never merge on red or missing CI, an unresolved review, or a stop condition. If any condition can't be met, leave the PR as it is, post a `BLOCKED:` comment saying which, and stop.

Observed criteria (human Studio playtests) do not block the merge. Put them in the final report and PR comment, and file any failure the human finds later as a defect issue.

## After merge
Once the PR is merged (by you, or by the human), clean up locally. GitHub deletes the remote branch on merge, so don't delete it yourself.
First confirm the merge: `gh pr view <pr> --json state -q .state` must print `MERGED`. `<root>` is the first path in `git worktree list`.
1. Update the root checkout's `main`, with `git -C <root>`, never by switching branches or stashing there:
   - if the root is on `main`: `git -C <root> pull --ff-only` (if it fails, for example on local commits or a dirty tree, leave it and say so in the report);
   - if the root is on another branch (in-progress work there): `git -C <root> fetch origin main:main`, which fast-forwards `main` without switching branches;
   - if `fetch` refuses because `main` is checked out in some other worktree, run `git -C <that worktree> pull --ff-only` there if it's clean; if it isn't, skip it and say so in the report.
2. Leave and remove the worktree. Your shell cwd resets on each call and a Claude Code session owns its cwd, so:
   - if this session created the worktree with EnterWorktree, call ExitWorktree with `remove` (pass `discard_changes` only after checking that the PR is `MERGED`, that `git rev-parse HEAD` equals the PR's `headRefOid`, and that `git status --short` is empty; a diff against `main` can't be used, because `main` may have moved on past the squash);
   - otherwise run `git -C <root> worktree remove <path>`. If it says the worktree is locked, `git -C <root> worktree unlock <path>` first. Use `--force` only when you've confirmed the leftovers are ignored files.
3. Delete the local branch from the root: `git -C <root> branch -D <branch>` (a squash merge makes `-d` refuse, which is why the `MERGED` check comes first). ExitWorktree `remove` already does this.
4. `git -C <root> worktree prune`, then check `git -C <root> worktree list` shows only worktrees still in use.

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

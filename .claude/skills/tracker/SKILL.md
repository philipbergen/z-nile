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

- **Numbering**: `f`, `d` and `c` share one number space; rafts have their own. `tracker/next` holds the next number of each (`issue <n> <phrase>`, `raft <n> <phrase>`). `new`, `new raft`, an emergent issue and `renumber` take the counter, counting by one, and push it raised, with a fresh phrase, in a lease push to `origin/main` (a lost race is retried on the new `main`); a number already in use is always passed. Offline (`PICKMAN_PUBLISH=0`) the local counter is read but never written. A tree without `tracker/next` (a fixture) keeps the old rule: the next multiple of 10 above the highest number in use.
- **Compaction**: `tracker.sh compact` renumbers every item from 0001, in a fresh worktree cut from `origin/main`, as one local commit to land by pull request; it refuses while another branch changes `tracker/` or `tests/acceptance/` (`--force` runs anyway), and writes the old-to-new map to `tracker/compaction.txt`. Merge the compaction PR only while `origin/main` still equals the sha in `tracker/compaction.txt`'s header; if `main` has moved, reset to `origin/main` and compact again (it is deterministic). On each branch that was in flight, run `tracker.sh remap` before merging `origin/main`: it takes the new ids and then merges `origin/main` itself. Never merge it plainly first: nothing detects the mixed tree afterwards. A branch that did merge plainly undoes that merge with `git reset --hard ORIG_HEAD`, then remaps. Any other tree from before the compaction refuses to publish until it merges `origin/main`.
- **Duplicate ids**: `tracker.sh audit` reports every problem in the tree (the gate runs it too). One id in two lifecycle folders blocks most commands: `tracker.sh renumber <directory>` renumbers that copy only: renumber the copy not in `done/` (normally the fresh backlog stub, for example `renumber tracker/issues/c0510`), because a done copy's specs are promoted under its id; a `done/` directory is refused.
- **Legacy layout**: documents used to be named with their slug. `tracker.sh migrate` renames any such document to `<ID>.md` and adds `slug:` to its frontmatter; run it, and commit, after merging a `main` that has the new layout.
- **Conflicts**: two branches that pick the same number now conflict in git, because both write `<ID>/<ID>.md`. Only a `CONFLICT (add/add)` on that path means two items share a number: run `git merge --abort`, `git fetch origin main`, then `tracker.sh renumber <ID>` on your own branch, which gives the item the number one above the highest of its kind in **both** your tree and `origin/main` (`f`, `d` and `c` share one space, rafts have their own), and merge again. `renumber <old> <new>` sets a number by hand. `renumber` rewrites every reference. A content conflict on a document is two edits to one item: resolve it like any merge, and never renumber.
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
Every change is made in its own git worktree under `<repo>/.worktree/` and lands by pull request (except tracker state, see Sync and claim). The main checkout stays on `main` and is never edited. Every job runs in a worktree under `<repo>/.worktree/`, never outside the repo directory: no sibling directory next to the repo, and not the harness's own `.claude/worktrees/`.

1. **The main checkout is read-only.** The complete list of commands that may run there:
   - `git fetch`, `scripts/tracker.sh sync` (a fast-forward there, which also rebuilds the board), and read-only inspection (`git status|log|diff|show|worktree list`);
   - `git worktree add|remove|prune` and `git branch -D <merged branch>`;
   - `scripts/setup.sh`, once, when bootstrapping a new machine (SETUP.md);
   - `scripts/tracker.sh ready` and `stop`, which publish to `origin/main`, fast-forward it there; `ready` writes the ignored `tracker/rafts/active/<R-id>/prompt.md` and `stop` removes it;
   - the read-only tracker commands `list`, `audit`, `find`, `members`, `metrics`, `workstreams`, `status` (without a target status), `prompt <R-id>` (it reads a readied raft's prompt and writes nothing), and the worktree commands `worktree` and `worktree-prune`. (`tracker.sh check` runs an item's checks and, for a raft, the full gate, so it runs in a worktree.)
   The tracker enforces part of this: `new`, `renumber`, `migrate`, `start`, `status <id> <to>`, `compact` and `remap` refuse to run in the main checkout of a repo that has an `origin`; `ready` and `stop` refuse to run anywhere else.
2. **Every change starts with a worktree**: `cd "$(scripts/tracker.sh worktree <target>)"`.

   | work | target | path and branch |
   |---|---|---|
   | executing a raft | `R0010` | `.worktree/R0010`, branch `R0010-<slug>` |
   | capturing an issue (make-issue) | `capture-<slug>` | `.worktree/capture-<slug>`, the same branch name; lands with `tracker.sh land`, no PR |
   | prepping a raft (ticket-prep) | `prep-<slug>`, the raft's slug | `.worktree/prep-<slug>`, the same branch name |
   | a skill, doc or config edit | `<area>-<slug>`, for example `skills-worktree-rule` | `.worktree/<area>-<slug>`, the same branch name |

   A change to skills, docs or tooling is still tracked work: it has an issue and normally a raft, and is executed in the raft's worktree like any other. Names are lowercase, so a prep worktree is named by the raft's slug: its id isn't known until `new raft` has run inside it. Use `tracker.sh worktree`, not the harness's own worktree feature: its directories aren't under `.worktree/`, and `worktree-prune` never sees them (it warns about any worktree outside `.worktree/` and leaves it). A worktree inside the repo also sees the main checkout's `.luaurc` as a parent configuration, so an alias a branch renames can still resolve locally: CI, which checks out the branch alone, is the final check.
3. **Starting execution**: the human starts a Claude session in the main checkout (which stays on `main`) and runs `/launch-raft <R-id>`. The skill reads the raft's prompt (`scripts/tracker.sh prompt <R-id> --path`) and `cd`s into `$(scripts/tracker.sh worktree <R-id>)`. The hooks follow the session's current directory, so from then on they act in the worktree; subagents get absolute worktree paths, because a subagent's shell resets its working directory on every call. Another agent gets the same text from `scripts/tracker.sh prompt <R-id>`.
4. **Prep merges before execution.** A prep PR merges (Landing a change) before `ready-raft` runs, so the raft's own worktree branches from an `origin/main` that has the prepped items. `ready-raft` never creates a raft: a raftless issue goes back to ticket-prep.

## Lifecycle: the directory and the status
- **Paths**: `tracker/{issues,rafts}/<ID>` is backlog, `…/active/<ID>` is in progress, and `…/done/<ID>` is finished. On `main`, `active/` holds the rafts that `ready` has handed out (and their issues), not only the branch you are on: the current raft is the active raft whose branch is the current branch.
- **The design field**: frontmatter `design:` moves `draft` → `reviewed` → `ready`, and only `ticket-prep` sets it.
- **Everything worked is a raft.** A raft has exactly one type (feature, defect or chore), and every member issue must match it. A lone issue gets a `single: true` raft made by ticket-prep in its prep worktree; `tracker.sh prompt <issue>` refuses to create one in the main checkout.
- **One raft = one branch (`R0010-<slug>`) = one PR.** In Phase 2B, temporary stream branches (`ws-<issue>`) feed the raft branch and are deleted.

| step | command | effect |
|---|---|---|
| ready | `tracker.sh ready <R-id\|issue-id>` | main checkout only, on a clean `main`, with an origin (ready-raft skill). Checks the raft and every member are `design: ready` with a `check.sh` that has a check, and that every `depends_on` outside the raft is `done`. Claims the raft, publishes one tracker-only commit that moves it and its members to `active/` on `origin/main` (every `check.sh` item path rewritten), pulls the main checkout, and writes the ignored `tracker/rafts/active/<R-id>/prompt.md`. On an active raft it regenerates the prompt and makes no commit. |
| stop | `tracker.sh stop <R-id>` | main checkout only, on a clean `main`, with an origin (stop-raft skill). Gives back a readied raft: publishes one tracker-only commit that moves it and its members from `active/` back to the backlog, stamped `prepared-…` (every `check.sh` item path rewritten back), removes `prompt.md`, pulls the main checkout, and names the raft's branch and PR, which it leaves as they are. A raft claimed by the legacy `start` (backlog, status `active`) gets a status-only publish and no move. A member in `done/` refuses. |
| start | `tracker.sh start R0010` | clean tree required. A readied raft (in `active/` on `origin/main`): creates the branch, makes an empty `tracker: start` commit, pushes, and opens a **draft** PR; it claims and moves nothing. A backlog raft (legacy): checks members are `design: ready` and every `depends_on` of a member that isn't a member of the raft is `done` on `origin/main` (an unknown id is refused too); if `start` refuses, merge `origin/main` and retry, never edit `depends_on` or move items to get past it: stop and report. It then claims, creates the branch, moves the raft and its members to `active/`, commits, pushes, and opens a **draft** PR. A worktree made before `ready` is told to `sync` first. Do this first, so the in-progress claim is visible right away. |
| worktree | `tracker.sh worktree <R-id\|name>` | creates or reuses `<repo>/.worktree/<R-id\|name>` on its own branch from a freshly fetched `origin/main` and prints its path. A raft's worktree is `.worktree/R0010` (branch `R0010-<slug>`); any other is `.worktree/<name>`. Refuses a done raft, and a branch that is checked out elsewhere. For a named worktree, `--from <ref>` cuts the new branch from that ref instead of `origin/main` (used for workstream streams: `tracker.sh worktree ws-<issue> --from <raft branch>`). |
| workstreams | `tracker.sh workstreams <R-id>` | read-only plan for parallel execution (execute-raft Phase 2B): issues in waves from `depends_on` and overlapping Touched modules, and a last line `parallel: yes (wave k: …)` or `parallel: no` |
| board | `tracker.sh board [--out PATH] [-O]` | writes the whole tracker as one self-contained HTML page, `.cache/board.html` by default (gitignored; the main checkout's copy is rebuilt after every tracker push to `origin/main` and every `sync` there, so reload the tab; elsewhere regenerate to refresh). Tabs Active / Waiting / Done (Waiting lists only rafts with no unfinished dependency), cursor keys, `/` then an id to jump to it, each raft's issues and dependencies rendered with the vendored marked. Then it opens the page in the default browser unless `-O` is given (`-O` only writes it, as CI and the specs do; `--open`, the old opt-in, is still accepted and is the default). `.github/workflows/board.yml` rebuilds it on every push to `main` and keeps it as the `tracker-board` Actions artifact: `rm -rf .cache/board-ci && gh run download -n tracker-board -D .cache/board-ci` fetches the latest into a fresh directory (gh won't overwrite an existing file, and `.cache/board.html` is the local default). |
| prune | `tracker.sh worktree-prune` | removes the worktree and branch of every raft that is in `done/` on `origin/main` (any merge strategy); keeps the rest, never forces, and lists named worktrees |
| focus | `tracker.sh focus f0010` | the following commits are attributed to that issue |
| commit | `tracker.sh commit -m "msg" [--issue f0010]... [--time 25]` | `git add -A`, then records spend rows in each issue's `spend.md` and the raft's summary **in the same commit**, adds `Issue:` trailers, and pushes |
| done | `tracker.sh done R0010` | requires the latest review round to be resolved (each finding answered `fixed <sha>: <what>; consequences: <what the fix could break, and how that was checked, or none>`, `refuted`, or, for a medium or low finding and only as execute-raft Phase 4 step 7 allows, `deferred <id>: <why>` naming a backlog issue) and the raft's `check.sh` to pass. In this order: promotes acceptance specs to `tests/acceptance/`, moves everything to `done/` (uncommitted), runs the full gate (`scripts/check.sh --full`) on that tree, marks the PR **ready** before its final push, commits, pushes, and appends spend to the PR body. A failing full gate rolls the tree back by itself (fix and re-run `done`). Inside a spec run (a fixture) it skips the full gate, says so, and checks only the promoted specs. If `done` is interrupted (Ctrl-C) during the gate, the tree is left promoted and moved but uncommitted: run `git reset --hard HEAD`, then re-run `done`. Likewise if it fails after marking the PR ready and before its commit: run `git reset --hard HEAD` and re-run `done` (marking ready twice is harmless); if only the push fails, run `git push`, then append `spend.md` to the PR body by hand |

## Landing a change
One procedure for every change: a raft, a capture, a prep or an edit.
0. **Sync first.** `scripts/tracker.sh sync` in the worktree (a fetch and a merge of `origin/main`).
   - If `main` brought the new document layout, run `scripts/tracker.sh migrate` and commit.
   - A `CONFLICT (add/add)` on a tracker document means two items picked the same number: see Conflicts.
   - Then run `scripts/tracker.sh list` (it fails on a duplicate id and warns when one number is shared by two prefixes; renumber yours if you can) and `scripts/check.sh --full`.
1. **Commit in the worktree**: `tracker.sh commit` inside a raft; plain `git add` and `git commit` elsewhere.
2. **Push and open the PR**: `git push -u origin <branch>`. A raft's PR is opened as a draft by `start`; any other PR is opened ready with `gh pr create`. A capture lands with `tracker.sh land` instead (no PR): it merges `origin/main`, runs `scripts/check.sh --full` locally, checks that only the sections, title and `depends_on` of draft backlog issue documents changed, pushes one commit to `main` (retrying a lost race) and prints the worktree-removal command.
3. **Merge** a PR only when the conditions under Merging hold, with `gh pr merge --squash`. A raft additionally needs `tracker.sh done` and a resolved review. A prep the user didn't ask for is not merged without asking, and a capture they didn't ask for is not landed without asking. (A capture has no PR: `tracker.sh land` in step 2 is its landing.)
4. **After the merge, one chained command, run last**: `"<root>/scripts/tracker.sh" sync; git -C <root> worktree remove <path> && git -C <root> branch -D <branch>; git -C <root> worktree prune`. `<root>` is the first path in `git worktree list`; `sync` fast-forwards the root and rebuilds its board. When the session works inside the worktree (with launch-raft it started in the main checkout and `cd`'d into the worktree), removing it removes the session's own directory, so every command after it must use `-C <root>` or absolute paths, and nothing should run after this command: post the final report first. The alternative is to leave removal to `tracker.sh worktree-prune`, run later from the main checkout.

## Merging
The agent that delivered the change merges its own PR once the evidence is in. Don't wait for a human. Merge only when **all** of these hold:
1. **For a raft**, `tracker.sh done` succeeded: the latest review round is resolved and the raft's `check.sh` passed. The PR is ready, not draft, and has no unresolved `BLOCKED:` comment. The results of the most recent review are already on the PR as a comment (execute-raft Phase 4). Only a *significant* finding in the final round's `review-NNN.md` (any high, or a failed Judged criterion) blocks the merge and engages the human; mediums and lows become follow-up issues (execute-raft Phase 4 step 7).
2. `scripts/check.sh --full` passes on the final head, run by you.
3. CI is green on the PR's exact head sha. `done` marks the PR ready before its final push, so the push starts the `pull_request` run on the final head (the `ready_for_review` event also starts a run, on the previous head; the poll ignores it because it looks at the final sha). Poll `gh pr view <pr> --json headRefOid,statusCheckRollup` until `headRefOid` equals `git rev-parse HEAD` and the `gate` check is `COMPLETED` with conclusion `SUCCESS`. Any other state is **not** green: a missing `gate`, `IN_PROGRESS`, or `SKIPPED` on the final sha means that sha was pushed while the PR was still a draft, so no run will follow by itself: dispatch one with `scripts/ci-verify.sh` (below); `FAILURE` is red. If no `gate` run for this sha appears within a few minutes of the push, dispatch one with `scripts/ci-verify.sh` (it needs HEAD equal to `origin/<branch>`, so push first) and wait. If the dispatched run fails, treat it as red.
   **The `beta` job too.** A PR that is ready for review from this repo also runs `beta`, which publishes the version to Pickman (Beta) and runs the runtime tests, so a merge needs it:
   - A missing `beta` check for the head sha means keep waiting, exactly like a missing `gate`.
   - A `workflow_dispatch` run never satisfies `beta` (it skips it). If no `pull_request` run appears within about 5 minutes of the `ready_for_review` event, re-fire that event with `gh pr ready --undo <pr> && gh pr ready <pr>`; use `ci-verify.sh` only to diagnose `gate`.
   - `beta` must be `COMPLETED` with conclusion `SUCCESS`. Unconfigured publishing ends `SUCCESS` with a warning, which is fine.
   - A red `beta` whose log shows `opencloud: ... failed with HTTP 429` or `HTTP 5xx` (500-599), from publishing, creating the task or polling it, or a publish `HTTP 409` (Roblox busy), is a transient Roblox failure whose retries ran out: rerun that job with `gh run rerun <run-id> --job <job-id>`, at most 3 times, then `BLOCKED:`. Any other red `beta` (HTTP 401, 403, 404 or another 4xx besides publish's 409, or a `FAIL` line without such a status) is a real failure: never rerun it; fix the cause, or post `BLOCKED:` when it isn't in this PR.
   - For a `CANCELLED` `beta`, run `gh run view <run-id> --json jobs`: a `beta` job with no steps was superseded by a newer ready PR (it never started), so rerun it with `gh run rerun <run-id> --job <job-id>` as often as needed until it finishes, but stop with `BLOCKED:` once 60 minutes have passed since the PR became ready, counted from the first ready event (re-firing it does not restart the count). A `beta` job whose steps ran was timed out or cancelled by hand: red. Judge `beta` only by the PR's own `pull_request` runs for the head sha: a `beta` that a dispatched run reports as `SKIPPED` never counts, for or against.
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
- `tracker.sh ready <id>`
- `tracker.sh metrics [--include-active]`
- `tracker.sh audit`
- `tracker.sh compact [--force]`
- `tracker.sh remap`

## Sync and claim
Tracker state is shared the moment it changes, not when a PR merges, so parallel terminals see each other's work.
- **Sync first.** Every skill that reads or changes tracker state starts with `scripts/tracker.sh sync` (a merge of `origin/main` in a worktree, a fast-forward in the main checkout). Reviewers and stream agents never merge: they run `scripts/tracker.sh sync --fetch`, which only updates `origin/main`, so the diff they judge does not move.
- **Statuses** (`status:` in an item's frontmatter): `new -> preparing -> prepared -> active -> done`. `design:` (draft, reviewed, ready) stays the design review's field. A missing `status:` is derived: `done/` is done, `active/` is active, `design: ready` is prepared, a draft item in a raft (or a draft raft) is preparing, anything else is new. `tracker.sh status` lists them from `origin/main`; `status <id>` prints one; `status <id> <to>` moves one, checked against `origin/main`. `done` is only ever set by `tracker.sh done`, and only `ready` (or the legacy `start` of a backlog raft) claims `active`, and `stop` gives a readied raft back.
- **Every write is stamped**: the stored value is `<state>-<three words>` (for example `preparing-quiet-copper-falcon`) and each write uses fresh words, so two terminals making the same move conflict in git instead of merging silently.
- **Published or carried.** These moves are pushed straight to `origin/main` as a tiny commit: `new issue` (the stub, `--desc "<line>"` is its Problem), `new raft` (claims its members), `status <id> preparing|new`, `status <id> prepared` back from `active`, and the claim made by `ready` (or by a legacy `start`). An emergent `new issue --raft <R-id>` and `renumber <id>` without `<new>` push a counter-only commit (the raised `tracker/next`) and then work locally. The move to `prepared` is **carried by the prep PR**: it only edits the local documents.
- **The direct-push exception.** Everything else lands by pull request. A published change is a tracker-only commit: only `tracker/(issues|rafts)/<ID>/<ID>.md` and `check.sh`, a `check.sh` only when it is created, an existing document only in its `status:` line (what `status`, `new raft` and `start` publish), and `tracker/next`, whose counters may only go up. The one other kind is a whole-directory move by `ready` or `stop`: every file of an item directory moves between the backlog and `active/` (never `done/`), byte for byte, except the document's `status:` line and the item paths in `check.sh`, which `paths.rewrite` changes to the new directory; publish recomputes both and refuses anything else. `tracker.sh land` also pushes a capture's edits to draft backlog issue documents (their sections, `title` and `depends_on`; design stays draft, every other frontmatter line unchanged) after a local full gate. Designs, reviews, code and acceptance specs never ride it. A commit that skips CI for the many tiny pushes is intended: `check.yml` ignores `tracker/**` on `push`, not on `pull_request`.
- **Claims.** Prep claims with `new raft` (issues must be `new`). An existing draft raft is claimed with `scripts/tracker.sh status <R-id> preparing`, which stamps the raft and its members; an issue added to a raft during prep is claimed first with `status <id> preparing`; one dropped is released with `status <id> new`. `ready` (and a legacy `start`) refuses a raft unless it and its members are `prepared` on `origin/main`; the claim is made by `ready`, not `start`.
- **A failed start.** `start` runs every local check before it claims. If a step after the claim fails (branch push, `gh pr create`), the local state is consistent: finish by hand (`git push -u origin <branch>`, `gh pr create --draft`), or give **your own** claim back with `status <R-id> prepared` (a raft started the legacy way, still in the backlog; a readied raft is given back only by `tracker.sh stop <R-id>`). The same terminal can re-run `start` if it died before moving anything (it remembers the claim in `.cache/tracker-claim-<R-id>`); another terminal is refused.
- **Offline.** `PICKMAN_PUBLISH=0` (or a repository without `origin`) keeps every command local, as it was before. Publishing and every other command that changes a repository first check that git's repository root is the checkout the tracker lives in; read-only commands do not.
- **Giving back a readied raft.** `status` refuses any item in `active/` on `origin/main` ("<id> is readied (in active/): use tracker.sh stop <R>"); `tracker.sh stop <R-id>` is the way to give back a readied raft, and it also gives back a raft claimed by the legacy `start`.
- **Whose claim.** A claim is not enforced against other terminals' give-backs (`stop` included): `status <R-id> prepared` from `active` (a legacy claim; a readied raft only through `stop`), `status <id> new` and `status <id> preparing` are open to anyone, so use them only for a claim that is yours (the user's decision: ownership is documented, not checked). Never give back a claim you did not make; ask the user.
- **Cutover.** A prep that was open before this landed exists only on its branch, so nothing on `origin/main` knows its raft id or members. Land such preps first, and renumber on a clash (see Conflicts). Do not stamp their members with `status <id> preparing`: a stamped member of a raft that is not on `origin/main` cannot be moved to `prepared` and can never be started.

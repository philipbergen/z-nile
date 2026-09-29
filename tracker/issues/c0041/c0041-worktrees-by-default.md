---
id: c0041
type: chore
title: Worktrees by default
raft: R0020
depends_on: []
emergent: false
design: reviewed
created: 2026-09-29
---

# c0041: Worktrees by default

## Problem
`tracker.sh start` runs `git switch -c` **in whatever checkout it's invoked from**. When R0010 was executed from the main checkout, that checkout moved to `R0010-foundation`. From then on, nobody could capture issues, prep rafts or run a second raft there without colliding with the running agent's files and commits.

Two more hazards follow from this:
- **A nested checkout gets committed.** Any checkout created *inside* the repo directory is swept into `git add -A`, which `tracker.sh commit` runs, on any branch that doesn't gitignore it.
- **The hooks check the wrong tree.** `scripts/hooks/*.sh` `cd` to the directory of the hook script, which is `$CLAUDE_PROJECT_DIR`. So in a session that works in another checkout, the Stop-hook gate checks the wrong tree.

The goal is for every raft to run in its own git worktree named after the raft, with the main checkout staying on `main`.

## Non-goals
- Changing `tracker.sh start` semantics beyond accepting an already-checked-out raft branch. c0010's sequestered lifecycle spec drives `start` in a remote-less clone and must keep passing unchanged.
- Automating the merge. The human still merges.
- Worktrees for issue capture or ticket-prep. Those stay on `main` in the main checkout.

## Solution
- **`tracker.sh worktree <R-id>`**: creates, or reuses, `.worktrees/<R-id>-<slug>` on branch `<R-id>-<slug>`, branched from `origin/main`, and prints its path.
- **`start`**: runs inside the worktree and reuses the branch.
- **`tracker.sh worktree-prune`**: removes worktrees whose raft is finished on the base branch.
- **`.worktrees/`** is gitignored.
- **Hooks** resolve the tree they act on from the hook input, not from their own location.
- **Draft PRs** are opened only when `origin` is a GitHub remote. That also makes worktree flows testable against a local bare remote.
- **Skills and the prompt**: execute-raft, the tracker skill and the prompt template make "worktree, then cd, then start" the first action.

## Design

**Naming.** For a raft `R0020` with slug `worktrees-by-default`:
- branch: `R0020-worktrees-by-default`
- worktree: `<main checkout>/.worktrees/R0020-worktrees-by-default`

Both come from one helper, `raftBranch(raft) = raft.id .. "-" .. raft.slug`, which `start` already computes inline. It is extracted and reused everywhere.

**`scripts/tracker/main.luau`**
- **`local function raftBranch(raft: store.Item): string`**: used by `start`, `worktree` and `worktree-prune`.
- **`local function mainRoot(): string`**: the main checkout's root, meaning the first `worktree` entry of `git worktree list --porcelain`. `worktree` always creates under `mainRoot()/.worktrees/`, even when invoked from inside another worktree.
- **`cmd.worktree(pos)`** (`worktree <R-id>`):
  1. The raft must exist (`store.get`) and be in **backlog** or **active**. Done rafts are refused.
  2. `git fetch --quiet origin`, only if an `origin` remote exists.
  3. `path = mainRoot() .. "/.worktrees/" .. raftBranch(raft)`.
  4. Then one of three cases:
     - **The path is already a registered worktree** (it's in `git worktree list --porcelain`): print the path, exit 0. This makes the command idempotent and resumable.
     - **Branch `raftBranch` exists locally or on origin**: `git worktree add <path> <branch>`. For an origin-only branch, first `git branch --track <branch> origin/<branch>`.
     - **Otherwise**: `git worktree add -b <branch> <path> <base>`, where `<base>` is `origin/main` if it exists, else `main`.
  5. Print **only the absolute path** on stdout, so that `cd "$(scripts/tracker.sh worktree R0020)"` works. Diagnostics go to stderr.
- **`cmd["worktree-prune"]`**:
  1. `git fetch --quiet origin`, if origin exists. The base is `origin/main`, or `main` if there's no origin.
  2. For each worktree under `mainRoot()/.worktrees/` named `<R-id>-<slug>`: the worktree is **finished** iff `git ls-tree -d <base> tracker/rafts/done/<R-id>` prints a line, meaning the raft reached `done/` on the base branch.
     - This works for **any merge strategy**. GitHub squash merges make `git branch --merged` useless.
     - A freshly created worktree with no commits counts as "merged" by ancestry but is **not** finished, so it's kept.
  3. For finished worktrees, run `git worktree remove <path>` and then `git branch -D <branch>`. The capital D is safe because the raft's content is on the base branch, and it's needed because squashed branches aren't ancestors.
  4. A worktree with uncommitted changes makes `git worktree remove` fail. Report it on stderr and continue; never `--force`.
  5. Print one line per removed worktree.
- **`cmd.start`**: if `git branch --show-current` already equals `raftBranch(raft)`, skip `git switch -c`. Otherwise, behave exactly as today. All other checks (backlog, clean tree, `design: ready`) are unchanged.
- **`local function onGitHub(): boolean`**: true iff `git remote get-url origin` succeeds and its output contains `github.com`.
  - `start`: push when origin exists, as today. Run `gh pr create` only when `onGitHub()`; otherwise print `origin is not GitHub: skipped draft PR`.
  - `done`: run `gh pr ready` / `gh pr edit` only when `hasUpstream() and onGitHub()`.
- **USAGE**: add both commands.

**`.gitignore`**: add `.worktrees/`.

**`scripts/hooks/post-edit.sh`**: after extracting `file`, run `cd "$(git -C "$(dirname "$file")" rev-parse --show-toplevel)"` and exit 0 if that fails, for example for a file outside any repo. Formatting and linting then use that tree's `stylua.toml` and `selene.toml`.

**`scripts/hooks/stop.sh`**:
- **Which tree**: extract `cwd` from the input JSON with the same `sed` approach used for `file_path`, then `cd "$(git -C "$cwd" rev-parse --show-toplevel)"`. Fall back to the script's repo when `cwd` is missing or not in a repo.
- **Loop guard**: the `stop_hook_active` guard is unchanged.

**Docs**:
- **execute-raft Phase 0**, step 2 becomes:
  ```
  cd "$(scripts/tracker.sh worktree R0010)"   # raft-named worktree + branch from origin/main
  scripts/tracker.sh start R0010
  ```
  All later commands run inside that worktree. Never switch branches in the main checkout.
  - After the human merges: `scripts/tracker.sh worktree-prune` from any checkout.
- **Tracker skill**: a "Worktrees" subsection covering naming, the one-raft-one-worktree rule, and that the main checkout stays on `main` for make-issue and ticket-prep. Add both commands to the lifecycle table.
- **`tracker/templates/prompt.md`**: hard rule 2 is prefixed with "work only in the raft's worktree (`cd "$(scripts/tracker.sh worktree {{RAFT_ID}})"`)".
- **SETUP.md**, "Agents on this host": one paragraph on worktrees and pruning.

### Scalability
- Worktrees share one object store, so creating one is cheap: a checkout of about 100 files.
- Each worktree has its own `.cache/`, so the gate's first run in a worktree downloads Roblox definitions once, about 1 MB.

### Maintainability
- One naming helper.
- `start` stays backward compatible, so existing specs and prompts still work.
- The GitHub check in one helper removes the hidden assumption "origin means GitHub".

### Usability
- Humans keep `main` checked out.
- Agents get a single copy-pasteable first command.
- Several rafts can run at once in separate worktrees.

### Touched modules
- `scripts/tracker/main.luau`
- `scripts/hooks`
- `.gitignore`
- `.claude/skills/execute-raft/SKILL.md`
- `.claude/skills/tracker/SKILL.md`
- `tracker/templates/prompt.md`
- `SETUP.md`

### Affected specs
`ALL`, because `scripts/` changes. New: `acceptance/worktree.spec.luau`.

## Unknowns & experiments
- **E1 (run in prep: PASS)**: can a worktree for `main` coexist while the main checkout is on another branch?
  - Yes: `git worktree add ../pickman.main main` was used to write this issue while R0010 ran in the main checkout.
- **E2 (run in prep: PASS)**: `.worktrees/` is gitignored, so it's invisible to `git status` and to the gate. The gate is safe because it only scans explicit roots: stylua and selene get `src tests scripts tracker`, `graph.build` gets `src tests`, `find tracker …`, and rojo only reads project `$path`s.
  - Result: see the acceptance spec case `main checkout stays clean`. Checked against the current tools; none of them recurses from the repo root.
- **E3**: does `git worktree list --porcelain` list the main checkout first, even when run from a linked worktree?
  - Git's documentation says the main worktree is always listed first. The acceptance spec runs `worktree` from inside a linked worktree to pin this.
  - Fallback: `git rev-parse --path-format=absolute --git-common-dir`, then its parent.

## Regression guard
- **c0010's sequestered `tracker-lifecycle.spec.luau`** (on the R0010 branch): its clone has no remote and runs `start` on `main`. That's the unchanged `switch -c` path. After both rafts merge, it runs in `tests/acceptance/c0010/` and must stay green.
- **Existing specs**: `tests/tooling/*` and `tests/meta` are unchanged.

## Test plan
`acceptance/worktree.spec.luau` sets up a scratch `.cache/wt-e2e/`:
- a bare `origin.git`, cloned from the repo's committed HEAD, with the working-tree `scripts/`, `tracker/templates/` and `.gitignore` overlaid and committed;
- a clone `main/` of that bare repo, with an empty tracker and a ready fixture raft `R0010` (slug `demo`) with issue `f0010`;
- the clone's origin is the local bare repo, so pushes are real and `gh` is never called.

Cases:
- `worktree creates a raft-named worktree and branch from origin/main` → AC1
- `worktree is idempotent and works from inside another worktree` → AC1
- `main checkout stays on main and clean` → AC1
- `start inside the worktree reuses the branch and pushes` → AC2
- `non-GitHub origin skips the draft PR` → AC2
- `worktree-prune removes squash-merged done rafts and keeps unfinished ones` → AC3
- `post-edit hook lints with the edited file's worktree config`, where the worktree's selene.toml allows a lint the main checkout denies → AC4
- `stop hook gates the session's cwd worktree` → AC4

## Acceptance criteria

### Checked
- **AC1**: `tracker.sh worktree <R>` creates, or reuses, `.worktrees/<R-id>-<slug>` on branch `<R-id>-<slug>` from origin/main. It prints only the absolute path, never moves the main checkout, and `.worktrees/` never shows up in the main checkout's `git status`.
- **AC2**: `start` inside that worktree reuses the branch, commits once, and pushes. It opens a draft PR only for GitHub origins.
- **AC3**: `worktree-prune` removes the worktree and branch of every raft that is in `done/` on the base branch, including after a squash merge. It keeps all other worktrees, including freshly created ones with no commits.
- **AC4**: The hooks act on the tree of the edited file (post-edit) or the session's `cwd` (stop), not on the tree the hook script lives in.
- **AC5**: The execute-raft skill and the prompt template make `cd "$(scripts/tracker.sh worktree …)"` the first action, and the tracker skill documents worktrees.

### Judged
None.

### Observed
None.

## Implementation steps
1. `.gitignore`, `raftBranch`, `mainRoot`, `onGitHub`; use them in `start` and `done`. Commit.
2. `cmd.worktree` and `cmd["worktree-prune"]`, plus USAGE. Commit.
3. Hooks. Commit.
4. Docs: execute-raft, tracker skill, prompt template, SETUP.md. Commit.
5. Run `scripts/tracker.sh check c0041` and `promote-check R0020`.

## Verification log

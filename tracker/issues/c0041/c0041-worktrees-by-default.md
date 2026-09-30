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
Work is done in whatever checkout the agent happens to be in, and several things go wrong:
- **`tracker.sh start` runs `git switch -c` in the checkout it's invoked from.** When R0010 was executed from the main checkout, that checkout moved to `R0010-foundation`. Nobody could capture issues, prep rafts or run a second raft there without colliding with the running agent's files and commits.
- **Capture and prep write straight to `main` in the main checkout.** `make-issue` and `ticket-prep` say "commit to main". So the main checkout is dirty or ahead while other work runs (R0040's executor found uncommitted c0400/R0060 prep files in it and had to work around them, because `start` needs a clean tree).
- **A nested checkout gets committed.** Any checkout created *inside* the repo directory is swept into `git add -A`, which `tracker.sh commit` runs, on any branch that doesn't gitignore it.
- **The hooks check the wrong tree.** `scripts/hooks/*.sh` `cd` to the directory of the hook script, which is `$CLAUDE_PROJECT_DIR`. So in a session that works in another checkout, the Stop-hook gate checks the wrong tree.
- **The prompt never says to create a worktree.** It only says to remove one after the merge.

The goal, decided by the user on 2026-09-30, is **the worktree rule**: the main checkout stays on `main` and is never edited. *Every* change (a raft, issue capture, ticket-prep, a skill or doc edit) is made in its own git worktree, delivered by pull request, merged by the agent once the merge conditions hold, and then pulled into the main checkout.

## Non-goals
- **Enforcing the rule mechanically** (a hook that denies edits in the main checkout). The rule is in the skills and the prompt, and the tooling makes the right thing the easy thing. A guard needs care around c0010's lifecycle spec, whose clone *is* a main checkout. It's a candidate follow-up, and not filed here.
- **A `tracker.sh land` command.** Landing (push, PR, wait for CI, merge, pull, clean up) stays a documented procedure built from `git` and `gh`, like the merge conditions in the tracker skill today.
- **Automatic removal of named (non-raft) worktrees** by `worktree-prune`. The landing procedure removes them; prune only lists the leftovers.
- Changing `tracker.sh start` semantics beyond accepting an already-checked-out raft branch. c0010's sequestered lifecycle spec drives `start` in a remote-less clone and must keep passing unchanged.

## Solution
- **`tracker.sh worktree <target>`**: creates, or reuses, a worktree under `<main checkout>/.worktrees/` on its own branch, branched from `origin/main`, and prints its path. The target is a raft id (`R0020`) or a plain name (`capture-raft-viewer`, `prep-R0060`, `skills-worktree-rule`).
- **`start`**: runs inside the raft's worktree and reuses its branch.
- **`tracker.sh worktree-prune`**: removes the worktrees of rafts that are finished on the base branch, and lists any other worktree it keeps.
- **`.worktrees/`** is gitignored.
- **Hooks** resolve the tree they act on from the hook input, not from their own location.
- **Draft PRs** are opened only when `origin` is a GitHub remote. That also makes worktree flows testable against a local bare remote.
- **Skills, prompt and AGENTS.md** state the worktree rule and a single **landing procedure**, and every skill that used to say "commit to main" or "switch to main" is changed to match.

## Design

### The worktree rule (as written into the skills)
1. **The main checkout is read-only.** It stays on `main`. The only commands run there are `git fetch`, `git pull --ff-only`, `git worktree add|remove|prune`, `git branch -D` of a merged branch, and read-only inspection. Nothing is edited, staged or committed there.
2. **Every change starts with a worktree**: `cd "$(scripts/tracker.sh worktree <target>)"`.

   | work | target | branch and path |
   |---|---|---|
   | executing a raft | `R0010` | `R0010-<slug>` at `.worktrees/R0010-<slug>` |
   | capturing an issue (make-issue) | `capture-<slug>` | `capture-<slug>` at `.worktrees/capture-<slug>` |
   | prepping a raft (ticket-prep) | `prep-<R-id>` | `prep-<R-id>` at `.worktrees/prep-<R-id>` |
   | a skill, doc or config edit | `<area>-<slug>`, for example `skills-worktree-rule` | the same name |

   A change to skills, docs or the tooling is still tracked work: it has an issue and normally a raft, and it is executed in the raft's worktree like any other.
3. **Landing** (the one procedure every change follows; the tracker skill has it in full):
   1. Commit in the worktree. `tracker.sh commit` inside a raft; plain `git add` and `git commit` for capture, prep and doc-only changes, which have no active raft.
   2. `git push -u origin <branch>`, then open the PR (a raft's PR is opened as a draft by `start`; any other PR is opened ready, `gh pr create`).
   3. Merge only when the tracker skill's "Merging" conditions hold: the agent ran `scripts/check.sh --full` on the final head, CI is green on that head sha, and the PR is `MERGEABLE` and `CLEAN`. Then `gh pr merge --squash`. A raft additionally needs `tracker.sh done` and the resolved review. Prep and capture that the user did not ask for are not merged without asking (memory rule: ask before new work).
   4. After the merge: `git -C <root> pull --ff-only`, `git -C <root> worktree remove <path>`, `git -C <root> branch -D <branch>`, `git -C <root> worktree prune`.
4. **Launching an agent**: the human starts it *inside* the worktree, `cd "$(scripts/tracker.sh worktree R0010)" && claude`. Then `$CLAUDE_PROJECT_DIR`, the hooks and every relative path already point at the right tree, and nothing depends on a `cd` persisting across tool calls (subagent shell calls reset their cwd). An agent that is started in the main checkout runs the `cd` as its first action and must use absolute worktree paths afterwards.
5. **Prep merges before execution.** Prep's PR merges (rule 3) before `make-prompt` runs. Its readiness check "main is pushed" then holds, and the raft's own worktree branches from an `origin/main` that has the prepped items.

### Naming and CLI
`raftBranch(raft) = raft.id .. "-" .. raft.slug` is extracted from `start` and reused everywhere.

**`scripts/tracker/main.luau`**
- **`local function mainRoot(): string`**: the main checkout's root, the first `worktree` entry of `git worktree list --porcelain`. Worktrees are always created under `mainRoot()/.worktrees/`, even when the command runs inside another worktree.
- **`local function onGitHub(): boolean`**: true iff `git remote get-url origin` succeeds and its output contains `github.com`.
- **`cmd.worktree(pos)`** (`worktree <target>`):
  1. **Classify** the target. It matches `^R%d%d%d%d$` → a raft. It matches `^[fdc]%d%d%d%d$` → error `give a raft id or a name`. It matches `^[a-z][a-z0-9-]*$` (at most 40 characters) → a named worktree. Anything else, including `/`, `..`, spaces or uppercase, → error `invalid worktree name`, before anything is created.
  2. **Raft targets** must exist (`store.get`) and be in backlog or active. A done raft is refused.
  3. `git fetch --quiet origin`, only if an `origin` remote exists.
  4. `branch` is `raftBranch(raft)` or the name. `path = mainRoot() .. "/.worktrees/" .. branch`.
  5. Then one of four cases:
     - **The path is already a registered worktree**: print the path, exit 0. The command is idempotent and resumable.
     - **The branch is checked out in another worktree** (for example the main checkout is still on it): print `<branch> is already used by worktree at <that path>` to stderr and exit 1. Nothing is created. (Git itself says `is already used by worktree at`, exit 128; the command checks `git worktree list --porcelain` first and reports its own exit code.)
     - **The branch exists locally or on origin**: `git worktree add <path> <branch>`. For an origin-only branch, first `git branch --track <branch> origin/<branch>`. This is how work resumes on another host or after a deleted worktree.
     - **Otherwise**: `git worktree add -b <branch> <path> <base>`, where `<base>` is `origin/main` if it exists, else `main`.
  6. Print **only the absolute path** on stdout, so `cd "$(scripts/tracker.sh worktree R0020)"` works. Diagnostics go to stderr.
- **`cmd["worktree-prune"]`**:
  1. `git fetch --quiet origin`, if origin exists. The base is `origin/main`, or `main` if there's no origin.
  2. Every git command runs with `-C mainRoot()`. A worktree that contains the current directory is skipped with a message, never removed from under the running command.
  3. For each worktree under `mainRoot()/.worktrees/` named `<R-id>-<slug>`: it is **finished** iff `git ls-tree -d <base> tracker/rafts/done/<R-id>` prints a line, meaning the raft reached `done/` **on the base branch**. That works for any merge strategy (GitHub squash merges make `git branch --merged` useless), and a raft moved to `done/` only on its own unmerged branch is not finished, so review fixes still land.
     - A freshly created worktree with no commits counts as merged by ancestry but is **not** finished, so it's kept.
  4. For a finished worktree, run `git worktree remove <path>` and then `git branch -D <branch>`. The capital D is safe because the raft's content is on the base branch, and it's needed because squashed branches aren't ancestors. **Never `--force`.** A worktree with modified or untracked files makes `git worktree remove` fail: name it on stderr, keep it and its branch, and continue.
  5. Any other worktree under `.worktrees/` (a named one) is left alone and listed as `kept <path> (named worktree: remove it when its PR has merged)`.
  6. Print one line per removed worktree. **Exit 1** if any finished worktree could not be removed, else 0.
- **`cmd.start`**: if `git branch --show-current` already equals `raftBranch(raft)`, skip `git switch -c`. Otherwise, behave exactly as today. All other checks (backlog, clean tree, `design: ready`) are unchanged.
- **Draft PRs**: `start` pushes when origin exists, as today, and runs `gh pr create --draft` only when `onGitHub()`; otherwise it prints `origin is not GitHub: skipped draft PR`. `done` runs `gh pr ready` and `gh pr edit` only when `hasUpstream() and onGitHub()`.
- **USAGE**: add both commands.

**`.gitignore`**: add `.worktrees/`.

### Hooks
The hooks read the tree from the hook input and use a form that really fails on a bad path (`cd ""` succeeds on macOS bash 3.2, so a bare `cd "$(…)" || exit 0` never exits).
- **`scripts/hooks/post-edit.sh`**: after extracting `file`:
  ```bash
  top=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null) || exit 0
  cd "$top" || exit 0
  ```
  Formatting and linting then use that tree's `stylua.toml` and `selene.toml`. A file outside any repo exits 0 without linting.
- **`scripts/hooks/stop.sh`**: extract `cwd` from the input JSON with the same `sed` approach used for `file_path`. If it is non-empty and inside a repo, `top=$(git -C "$cwd" rev-parse --show-toplevel)` and `cd "$top"`, so a session sitting in `src/shared` gates the worktree root. Otherwise fall back to the script's own repo. The `stop_hook_active` guard is unchanged.

### Docs (each is checked by AC5 and ruled on by JC1)
- **`AGENTS.md`**: one added line under the non-negotiables: every change is made in a worktree and lands by PR (see the tracker skill).
- **tracker skill**: a "Worktrees" section (the rule, the target table, launching an agent), a "Landing a change" section (the procedure above) that the "Merging" and "After merge" sections refer to, and both commands in the lifecycle table. "Merging" becomes the merge conditions for *any* PR, with the raft-only additions marked.
- **execute-raft**: Phase 0 step 1 becomes `cd "$(scripts/tracker.sh worktree R0010)"` and then confirming the gate there; step 2 is `tracker.sh start`. "Never switch branches in the main checkout." Phase 6 refers to the landing procedure.
- **make-issue**: step 6 becomes a worktree `capture-<slug>`, commit, PR, merge, pull.
- **ticket-prep**: step 6 becomes a worktree `prep-<R-id>` used for the whole prep (design, specs, reviews), one prep commit, PR, merge, pull. The "ask before committing to main" line becomes "ask before merging prep the user did not request".
- **make-prompt**: readiness is checked in a read-only way from the main checkout after `git pull --ff-only`; the report ends with the launch line `cd "$(scripts/tracker.sh worktree R…)" && claude`.
- **review**: design mode "runs on main before any PR exists" becomes "runs in the prep worktree; its files ride in the prep PR".
- **`tracker/templates/prompt.md`**: hard rule 2 is prefixed with "your working directory is the raft's worktree: your first action is `cd "$(scripts/tracker.sh worktree {{RAFT_ID}})"`", and the Environment section says never to edit the main checkout.
- **SETUP.md**, "Agents on this host": one paragraph on worktrees, the launch line and pruning.

### Scalability
- Worktrees share one object store, so creating one is cheap: a checkout of about 100 files.
- Each worktree has its own `.cache/`, so the gate's first run in a worktree downloads Roblox definitions once, about 1 MB.
- Every capture and prep now costs a PR and one CI run (PRs that are not drafts run the gate). That's the price of a main checkout that is never dirty.

### Maintainability
- One naming helper, one landing procedure, and every skill points at them rather than restating them.
- `start` stays backward compatible, so existing specs and prompts still work.
- The GitHub check in one helper removes the hidden assumption "origin means GitHub".

### Usability
- Humans keep `main` checked out, current and clean, whatever agents are running.
- Agents get a single copy-pasteable first command, and the human gets a single launch line.
- Several rafts and several captures can be in flight at once. Issue numbers assigned in separate unmerged worktrees can collide; `tracker.sh renumber` on rebase already covers that (tracker skill, "Conflicts").

### Touched modules
- `scripts/tracker/main.luau`
- `scripts/hooks`
- `.gitignore`
- `AGENTS.md`
- `SETUP.md`
- `tracker/templates/prompt.md`
- `.claude/skills/execute-raft/SKILL.md`
- `.claude/skills/tracker/SKILL.md`
- `.claude/skills/make-issue/SKILL.md`
- `.claude/skills/ticket-prep/SKILL.md`
- `.claude/skills/make-prompt/SKILL.md`
- `.claude/skills/review/SKILL.md`

### Affected specs
`lune run scripts/affected -- scripts/tracker/main.luau scripts/hooks .gitignore tracker/templates/prompt.md` prints `ALL`, because `scripts/` and config files force a full run. New: `acceptance/worktree.spec.luau`.

## Unknowns & experiments
- **E1 (run in prep: PASS)**: can a worktree for `main` coexist while the main checkout is on another branch? Yes: this issue's own prep ran in `../pickman-c0041` while the main checkout was on `main`, and R0040 ran in `../pickman-R0040` beside a dirty main checkout.
- **E2 (run in prep: PASS)**: `.worktrees/` is gitignored, so it's invisible to `git status` and to the gate. The gate only scans explicit roots: stylua and selene get `src tests scripts tracker`, `graph.build` gets `src tests`, `find tracker …`, and rojo only reads project `$path`s. The spec case `main checkout stays on main and clean` pins it.
- **E3**: does `git worktree list --porcelain` list the main checkout first, even when run from a linked worktree? Git's documentation says so. The spec runs `worktree` from inside a linked worktree to pin it. Fallback: `git rev-parse --path-format=absolute --git-common-dir`, then its parent.
- **E4**: does the Stop hook input's `cwd` follow a `cd` made in a Bash tool call?
  - It's unproven, so nothing depends on it: the primary path is launching the agent inside the worktree (rule 4), where `$CLAUDE_PROJECT_DIR` and `cwd` are the worktree from the start.
  - The executor may test it (log stdin from a throwaway hook) and record the result in the Verification log; either answer leaves the design valid.
- **E5 (run in prep: PASS)**: on git 2.54 and macOS bash 3.2, `git worktree add <path> <branch>` for a branch checked out elsewhere fails with `fatal: '<branch>' is already used by worktree at '<path>'`, exit 128; and `cd ""` returns 0. That's why `worktree` checks the porcelain list itself, and why the hooks assign first and then `|| exit 0`.

- **E6 (run in prep: PASS)**: can the designed tooling satisfy the sequestered spec, and does the spec catch wrong implementations?
  - A throwaway prototype (about 130 lines in `scripts/tracker/main.luau` plus 3 to 5 lines in each hook and `.gitignore`, reverted, not committed) passes all 20 spec cases, run from a feature branch (not `main`), and `scripts/check.sh --full` passes with it: 328 specs, including c0010's lifecycle spec.
  - Four planted mistakes each failed exactly the case written to catch it: prune passing `--force` (the dirty and run-from-inside cases); "finished" judged on the worktree's own branch instead of the base (the unmerged-done case); `onGitHub()` always false (the GitHub-origin case); the stop hook using `cwd` without `rev-parse --show-toplevel` (the subdirectory case).
  - The prototype needed one strict-mode fix: a worktree-list parser typed with an optional entry failed type checking until the accumulator was non-optional.

## Regression guard
- **c0010's sequestered `tracker-lifecycle.spec.luau`** (`tests/acceptance/c0010/`): its clone has no remote and runs `start` on `main`. That's the unchanged `switch -c` path, and it must stay green.
- **Existing specs**: `tests/tooling/*` and `tests/meta` are unchanged.
- **Every later raft's gate** runs this issue's promoted spec, so the spec must not depend on the branch or detached state of the checkout it runs from (F1 of design-review-001: the fixture pins its own `main`).

## Test plan
`acceptance/worktree.spec.luau` sets up a scratch `.cache/wt-e2e/`:
- a bare `origin.git`, cloned from the repo's committed HEAD, **with `main` forced as the fixture's branch** so the spec passes from any branch or a detached HEAD, with the working-tree `scripts/`, `tracker/templates/` and `.gitignore` overlaid and committed;
- a clone `main/` of that bare repo, with an empty tracker and two ready fixture rafts, `R0010` (`demo`) with issue `f0010`, and `R0020` (`other`) with issue `f0020`;
- the clone's origin is the local bare repo, so pushes are real and `gh` is never called, except in the GitHub case, which puts a fake `gh` first on `PATH`.

Cases (`spec case → AC`):
- `worktree creates a raft-named worktree and branch from origin/main` → AC1
- `worktree is idempotent and works from inside another worktree` → AC1
- `main checkout stays on main and clean` → AC1
- `worktree resumes an existing branch after its worktree is deleted` → AC1 (F10)
- `worktree refuses a branch checked out elsewhere` → AC1 (F10)
- `start inside the worktree reuses the branch and pushes` → AC2
- `non-GitHub origin skips the draft PR` → AC2
- `GitHub origin opens the draft PR` → AC2 (F3): origin's fetch URL is `https://github.com/x/y.git` and its pushurl is the bare repo, and a fake `gh` records its argv; the case asserts `pr create` and `--draft` were passed.
- `worktree-prune removes squash-merged done rafts and keeps unfinished ones` → AC3
- `worktree-prune keeps a raft that is done only on its own unmerged branch` → AC3 (F4)
- `worktree-prune never forces: a dirty finished worktree survives and the exit code is 1` → AC3 (F5)
- `worktree-prune run from inside a finished worktree skips it` → AC3 (F9)
- `worktree-prune lists a named worktree and leaves it` → AC3
- `post-edit hook lints with the edited file's worktree config` → AC4
- `post-edit hook ignores a file outside any repository` → AC4 (F8)
- `stop hook gates the session's cwd worktree` → AC4
- `stop hook gates the worktree root when cwd is a subdirectory` → AC4 (F8)
- `worktree creates a named worktree from origin/main` → AC6
- `worktree rejects bad names and non-raft ids` → AC6
- `worktree refuses a done raft` → AC6

`check.sh` runs the spec **once** per check into a variable, fails a check if the spec did not load (`could not load spec`) or if a named case is missing from the runner's output entirely, and only then looks at that check's case names (F6).

## Acceptance criteria

### Checked
- **AC1**: `tracker.sh worktree <R>` creates, or reuses, `.worktrees/<R-id>-<slug>` on branch `<R-id>-<slug>` from origin/main. It prints only the absolute path, never moves the main checkout, resumes from an existing branch, refuses a branch checked out elsewhere, and `.worktrees/` never shows up in the main checkout's `git status`.
- **AC2**: `start` inside that worktree reuses the branch, commits once, and pushes. It opens a draft PR for GitHub origins (`gh pr create --draft`) and skips it, with a message, for others.
- **AC3**: `worktree-prune` removes the worktree and branch of every raft that is in `done/` on the base branch, including after a squash merge. It keeps everything else: unfinished rafts, freshly created worktrees, a raft done only on its own unmerged branch, a dirty worktree (exit 1, never `--force`), the worktree it runs in, and named worktrees (listed).
- **AC4**: The hooks act on the tree of the edited file (post-edit) or the session's `cwd`, or its repo root when `cwd` is a subdirectory (stop), not on the tree the hook script lives in.
- **AC5**: The skills, prompt template and AGENTS.md carry the worktree rule: the named files contain `scripts/tracker.sh worktree`, the tracker skill has "Worktrees" and "Landing a change" sections, and none of the skills or the template tells the reader to switch to, edit or commit on `main` in the main checkout (the negative grep in `check.sh`).
- **AC6**: `tracker.sh worktree <name>` creates, or reuses, `.worktrees/<name>` on branch `<name>` from origin/main for a valid plain name, and rejects invalid names, item ids that aren't rafts, and done rafts, creating nothing.

### Judged
- **JC1: the skills leave no path that mutates the main checkout.**
  - **Pass**: for each of execute-raft, make-issue, ticket-prep, make-prompt, review, tracker, the prompt template, AGENTS.md and SETUP.md, every instruction that edits, stages, commits, switches branches, or runs a gate does so in a worktree; the only main-checkout commands are the read-only and `pull --ff-only` ones listed in the worktree rule; and the landing procedure is stated once (tracker skill) and referenced, not contradicted, elsewhere.
  - **Fail**: any instruction that says to commit, switch or edit in the main checkout or "on main", or two documents that disagree about the procedure. Quote each offending line.

### Observed
None.

## Implementation steps
1. `.gitignore`, `raftBranch`, `mainRoot`, `onGitHub`; use them in `start` and `done`. Commit.
2. `cmd.worktree` (raft and named targets) and `cmd["worktree-prune"]`, plus USAGE. Commit.
3. Hooks. Commit.
4. Docs: AGENTS.md, the six skills, the prompt template, SETUP.md. Commit.
5. Run `scripts/tracker.sh check c0041` and `promote-check R0020`. Optionally record E4.

## Verification log

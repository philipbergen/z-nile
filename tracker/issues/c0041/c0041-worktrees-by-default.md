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
- **A hook that denies edits made by other tools** (Edit, Write, plain `git`) in the main checkout. The tracker CLI does refuse its own mutations there (see Design), and the rule is in the skills and the prompt, but a hook is a separate follow-up, not filed here.
- **A `tracker.sh land` command.** Landing (fetch, merge, gate, push, PR, wait for CI, merge, pull, clean up) stays a documented procedure built from `git` and `gh`, like the merge conditions in the tracker skill today.
- **Automatic removal of named (non-raft) worktrees** by `worktree-prune`. The landing procedure removes them; prune only lists the leftovers.
- Changing `tracker.sh start` semantics beyond accepting an already-checked-out raft branch and refusing to run in the main checkout. c0010's sequestered lifecycle spec drives `start` in a remote-less clone and must keep passing unchanged.

## Solution
- **`tracker.sh worktree <target>`**: creates, or reuses, a worktree under `<main checkout>/.worktrees/` on its own branch, branched from a freshly fetched `origin/main`, and prints its path. The target is a raft id (`R0020`) or a plain lowercase name (`capture-raft-viewer`, `prep-raft-browser`, `skills-worktree-rule`).
- **`start`**: runs inside the raft's worktree and reuses its branch. `start`, `new`, `renumber` and a raft-creating `prompt` **refuse to run in the main checkout** when the repo has an `origin`.
- **`store.find`** errors on a duplicate item id, so a collision between concurrently created items is detected instead of one item silently disappearing.
- **`tracker.sh worktree-prune`**: removes the worktrees of rafts that are finished on the base branch, and lists any other worktree it keeps.
- **`.worktrees/`** is gitignored.
- **Hooks** resolve the tree they act on from the hook input, not from their own location.
- **Draft PRs** are opened only when `origin` is a GitHub remote. That also makes worktree flows testable against a local bare remote.
- **Skills, prompt, settings and AGENTS.md** state the worktree rule and a single **landing procedure**, and every instruction that used to say "commit to main", "switch to main" or "diff against main" is changed to match.

## Design

### The worktree rule (as written into the skills)
1. **The main checkout is read-only.** It stays on `main`, and *nothing is edited, staged or committed there*. The complete list of commands that may run in it:
   - `git fetch`, `git pull --ff-only`, and read-only inspection (`git status|log|diff|show|worktree list`);
   - `git worktree add|remove|prune` and `git branch -D <merged branch>`;
   - `scripts/setup.sh`, once, when bootstrapping a new machine (SETUP.md);
   - the read-only tracker commands `list`, `find`, `members`, `check`, `metrics`, `prompt <R-id>`, and the worktree commands `worktree` and `worktree-prune`.
2. **Every change starts with a worktree**: `cd "$(scripts/tracker.sh worktree <target>)"`.

   | work | target | branch and path |
   |---|---|---|
   | executing a raft | `R0010` | `R0010-<slug>` at `.worktrees/R0010-<slug>` |
   | capturing an issue (make-issue) | `capture-<slug>` | `capture-<slug>` at `.worktrees/capture-<slug>` |
   | prepping a raft (ticket-prep) | `prep-<slug>`, the raft's slug | `prep-<slug>` at `.worktrees/prep-<slug>` |
   | a skill, doc or config edit | `<area>-<slug>`, for example `skills-worktree-rule` | the same name |

   A change to skills, docs or the tooling is still tracked work: it has an issue and normally a raft, and it is executed in the raft's worktree like any other. Names are lowercase, so a prep worktree is named by the raft's slug: the raft id isn't known until `new raft` has run inside it.

   **Use `tracker.sh worktree`, not the harness's `EnterWorktree`.** EnterWorktree creates worktrees under `.claude/worktrees/`, which is not gitignored and which `worktree-prune` never sees.
3. **Landing** (the one procedure every change follows; the tracker skill has it in full):
   0. **Sync first**: `git fetch origin main && git merge origin/main` in the worktree, run `scripts/check.sh --full`, and if two items now share an id (`store.find` reports `duplicate id`), `tracker.sh renumber` yours and commit. Captures and preps run concurrently and pick their ids from their own base, so this step is what catches a collision before it merges.
   1. Commit in the worktree: `tracker.sh commit` inside a raft (it needs an active raft); plain `git add` and `git commit` for capture, prep and doc-only changes, which have none.
   2. `git push -u origin <branch>`, then open the PR (a raft's PR is opened as a draft by `start`; any other PR is opened ready, `gh pr create`).
   3. Merge only when the tracker skill's "Merging" conditions hold: the agent ran `scripts/check.sh --full` on the final head, CI is green on that head sha, and the PR is `MERGEABLE` and `CLEAN`. Then `gh pr merge --squash`. A raft additionally needs `tracker.sh done` and the resolved review. Prep and capture that the user did not ask for are not merged without asking (memory rule: ask before new work).
   4. **After the merge, one chained command, run last**: `git -C <root> pull --ff-only; git -C <root> worktree remove <path> && git -C <root> branch -D <branch>; git -C <root> worktree prune`. When the agent was launched inside the worktree (rule 4), removing it removes the session's own directory, so nothing runs after this command: post the final report first. If the agent prefers, it leaves removal to `tracker.sh worktree-prune` run later from the main checkout.
4. **Launching an agent**: the human starts it *inside* the worktree, `cd "$(scripts/tracker.sh worktree R0010)" && claude`. Then `$CLAUDE_PROJECT_DIR`, the hooks and every relative path already point at the right tree, and nothing depends on a `cd` persisting across tool calls (subagent shell calls reset their cwd). An agent that is started in the main checkout runs the `cd` as its first action and must use absolute worktree paths afterwards.
5. **Prep merges before execution.** Prep's PR merges (rule 3) before `make-prompt` runs. Its readiness check "main is pushed" then holds, and the raft's own worktree branches from an `origin/main` that has the prepped items. `make-prompt` never creates a raft: a raftless issue goes back to ticket-prep.

### Naming and CLI
`raftBranch(raft) = raft.id .. "-" .. raft.slug` is extracted from `start` and reused everywhere.

**`scripts/tracker/main.luau`**
- **`local function mainRoot(): string`**: the main checkout's root, the first `worktree` entry of `git worktree list --porcelain`. Worktrees are always created under `mainRoot()/.worktrees/`, even when the command runs inside another worktree.
- **`local function onGitHub(): boolean`**: true iff `git remote get-url origin` succeeds and its output contains `github.com`.
- **`local function refuseInMainCheckout(what: string)`**: if an `origin` remote exists and `git rev-parse --show-toplevel` equals `mainRoot()`, fail with `{what} must run inside a worktree: cd "$(scripts/tracker.sh worktree <target>)"`. A repo with no origin (c0010's lifecycle spec clone, other tests) is never refused. Called by `new`, `renumber`, `start` (unless the current branch is already `raftBranch(raft)`) and by `prompt` when it would create a placeholder raft.
- **`cmd.worktree(pos)`** (`worktree <target>`):
  1. **Classify** the target. It matches `^R%d%d%d%d$` → a raft. It matches `^[fdc]%d%d%d%d$` → error `give a raft id or a name`. It matches `^[a-z][a-z0-9-]*$` (at most 40 characters) → a named worktree. Anything else, including `/`, `..`, spaces or uppercase, → error `invalid worktree name`, before anything is created.
  2. **Raft targets** must exist (`store.get`) and be in backlog or active. A done raft is refused.
  3. `git worktree prune`, so a registered worktree whose directory was deleted is forgotten (git otherwise refuses `is a missing but already registered worktree`), then `git fetch --quiet origin`, only if an `origin` remote exists.
  4. `branch` is `raftBranch(raft)` or the name. `path = mainRoot() .. "/.worktrees/" .. branch`.
  5. Then one of four cases:
     - **The path is already a registered worktree**: print the path, exit 0. The command is idempotent and resumable.
     - **The branch is checked out in another worktree** (for example the main checkout is still on it): print `<branch> is already used by worktree at <that path>` to stderr and exit 1. Nothing is created. (Git itself says `is already used by worktree at`, exit 128; the command checks `git worktree list --porcelain` first and reports its own exit code.)
     - **The branch exists locally or on origin**: `git worktree add <path> <branch>`. For an origin-only branch, first `git branch --track <branch> origin/<branch>`. This is how work resumes on another host or after a deleted worktree.
     - **Otherwise**: `git worktree add --no-track -b <branch> <path> <base>`, where `<base>` is the freshly fetched `origin/main` if it exists, else `main`. `--no-track` keeps the new branch from tracking `origin/main`, so a bare `git push` can't target the wrong ref before `start` or landing sets the upstream.
  6. Print **only the absolute path** on stdout, so `cd "$(scripts/tracker.sh worktree R0020)"` works. Diagnostics go to stderr.
- **`cmd["worktree-prune"]`**:
  1. `git worktree prune`, then `git fetch --quiet origin`, if origin exists. The base is `origin/main`, or `main` if there's no origin.
  2. Every git command runs with `-C mainRoot()`. A worktree that contains the current directory is skipped with a message, never removed from under the running command.
  3. For each worktree under `mainRoot()/.worktrees/` named `<R-id>-<slug>`: it is **finished** iff `git ls-tree -d <base> tracker/rafts/done/<R-id>` prints a line, meaning the raft reached `done/` **on the base branch**. That works for any merge strategy (GitHub squash merges make `git branch --merged` useless), and a raft moved to `done/` only on its own unmerged branch is not finished, so review fixes still land.
     - A freshly created worktree with no commits counts as merged by ancestry but is **not** finished, so it's kept.
  4. For a finished worktree, run `git worktree remove <path>` and then `git branch -D <branch>`. The capital D is safe because the raft's content is on the base branch, and it's needed because squashed branches aren't ancestors. **Never `--force`.** A worktree with modified or untracked files makes `git worktree remove` fail: name it on stderr, keep it and its branch, and continue.
  5. Any other worktree under `.worktrees/` (a named one) is left alone and listed as `kept <path> (named worktree: remove it when its PR has merged)`.
  6. Print one line per removed worktree. **Exit 1** if any finished worktree could not be removed, else 0.
- **`cmd.start`**: if `git branch --show-current` already equals `raftBranch(raft)`, skip `git switch -c`; otherwise call `refuseInMainCheckout("start")` first and then behave exactly as today. All other checks (backlog, clean tree, `design: ready`) are unchanged.
- **Draft PRs**: `start` pushes when origin exists, as today, and runs `gh pr create --draft` only when `onGitHub()`; otherwise it prints `origin is not GitHub: skipped draft PR`. `done` runs `gh pr ready` and `gh pr edit` only when `hasUpstream() and onGitHub()`.
- **USAGE**: add both commands.

**`scripts/tracker/store.luau`**: `store.find(id)` errors `duplicate id <id>: <the directories or documents>` when an item's directory holds more than one `<id>-*.md`, or the same id exists in more than one state directory. `list`, `check`, `members` and `prompt` then fail loudly instead of returning whichever item `readDir` yielded first. (Two branches that each add `c0420` produce differently named docs and byte-identical `check.sh` files, so `git merge` sees no conflict and one item would otherwise vanish.)

**`.gitignore`**: add `.worktrees/`.

**`.claude/settings.json`**: add `Bash(scripts/tracker.sh worktree:*)` and `Bash(scripts/tracker.sh worktree-prune:*)` to `permissions.allow`, so the prompt's first command doesn't block on a permission prompt.

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
- **tracker skill**:
  - a "Worktrees" section (the rule with its command whitelist, the target table, the EnterWorktree prohibition, launching an agent) and a "Landing a change" section (the procedure above, steps 0 to 4);
  - both commands in the lifecycle table;
  - the "don't commit tracked work with a plain `git commit`" line becomes "use `tracker.sh commit` inside a raft; plain `git` for capture, prep and doc-only worktrees (see Landing a change)";
  - "Merging" becomes the merge conditions for *any* PR, with the raft-only additions marked;
  - "After merge" is replaced by landing step 4; the "root is on another branch" and EnterWorktree/ExitWorktree paragraphs are deleted.
- **execute-raft**: Phase 0 step 1 becomes `cd "$(scripts/tracker.sh worktree R0010)"` and then confirming the gate there; step 2 is `tracker.sh start`. "Never switch branches in the main checkout." Phase 4's reviewer input becomes `git fetch origin main && git diff origin/main...HEAD` (the local `main` is no longer kept current). Phase 5 step 2 merges `origin/main`. Phase 6 refers to the landing procedure.
- **make-issue**: step 6 becomes a worktree `capture-<slug>`, commit, PR, merge, pull.
- **ticket-prep**: step 1 runs in a worktree `prep-<slug>` that is used for the whole prep (`new raft`, design, specs, reviews). Step 6 becomes one prep commit, PR, merge, pull, replacing "commit to main". "Ask before committing to main" becomes "ask before merging prep the user did not request".
- **make-prompt**: readiness is checked from the main checkout after `git pull --ff-only`, read-only. A raftless issue is not wrapped by make-prompt: it goes back to ticket-prep (which creates the raft, `--single` for a lone issue, in its worktree). The report ends with the launch line `cd "$(scripts/tracker.sh worktree R…)" && claude`.
- **review**: design mode "runs on main before any PR exists" becomes "runs in the prep worktree; its files ride in the prep PR"; code mode's `git diff main...HEAD` becomes `git diff origin/main...HEAD`.
- **`tracker/templates/prompt.md`**: hard rule 2 is prefixed with "your working directory is the raft's worktree: your first action is `cd "$(scripts/tracker.sh worktree {{RAFT_ID}})"`", and the Environment section says never to edit the main checkout.
- **SETUP.md**, "Agents on this host": one paragraph on worktrees, the launch line and pruning. The troubleshooting row saying `tracker.sh start` needs an `origin` and fails on `gh pr create` is corrected: `start` skips the draft PR for a non-GitHub origin.

### Scalability
- Worktrees share one object store, so creating one is cheap: a checkout of about 100 files.
- Each worktree has its own `.cache/`, so the gate's first run in a worktree downloads Roblox definitions once, about 1 MB.
- Every capture and prep now costs a PR and one CI run (PRs that are not drafts run the gate). That's the price of a main checkout that is never dirty.

### Maintainability
- One naming helper, one landing procedure, one main-checkout guard, and every skill points at them rather than restating them.
- `start` stays backward compatible, so existing specs and prompts still work.
- The GitHub check in one helper removes the hidden assumption "origin means GitHub".

### Usability
- Humans keep `main` checked out, current and clean, whatever agents are running.
- Agents get a single copy-pasteable first command, and the human gets a single launch line.
- Several rafts and several captures can be in flight at once. Issue numbers assigned in separate unmerged worktrees can collide, and landing step 0 plus `store.find`'s duplicate error make that visible before the merge; `tracker.sh renumber` (tracker skill, "Conflicts") resolves it.

### Touched modules
- `scripts/tracker/main.luau`
- `scripts/tracker/store.luau`
- `scripts/hooks`
- `.gitignore`
- `.claude/settings.json`
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
`lune run scripts/affected -- scripts/tracker/main.luau scripts/tracker/store.luau scripts/hooks .gitignore tracker/templates/prompt.md` prints `ALL`, because `scripts/` and config files force a full run. New: `acceptance/worktree.spec.luau`.

## Unknowns & experiments
- **E1 (run in prep: PASS)**: can a worktree for `main` coexist while the main checkout is on another branch? Yes: this issue's own prep ran in `../pickman-c0041` while the main checkout was on `main`, and R0040 ran in `../pickman-R0040` beside a dirty main checkout.
- **E2 (run in prep: PASS)**: `.worktrees/` is gitignored, so it's invisible to `git status` and to the gate. The gate only scans explicit roots: stylua and selene get `src tests scripts tracker`, `graph.build` gets `src tests`, `find tracker …`, and rojo only reads project `$path`s. The spec case `main checkout stays on main and clean` pins it.
- **E3**: does `git worktree list --porcelain` list the main checkout first, even when run from a linked worktree? Git's documentation says so. The spec runs `worktree` from inside a linked worktree to pin it. Fallback: `git rev-parse --path-format=absolute --git-common-dir`, then its parent.
- **E4**: does the Stop hook input's `cwd` follow a `cd` made in a Bash tool call?
  - It's unproven, so nothing depends on it: the primary path is launching the agent inside the worktree (rule 4), where `$CLAUDE_PROJECT_DIR` and `cwd` are the worktree from the start.
  - The executor may test it (log stdin from a throwaway hook) and record the result in the Verification log; either answer leaves the design valid.
- **E5 (run in prep: PASS)**: on git 2.54 and macOS bash 3.2, `git worktree add <path> <branch>` for a branch checked out elsewhere fails with `fatal: '<branch>' is already used by worktree at '<path>'`, exit 128; `cd ""` returns 0; a worktree directory deleted with `rm -rf` stays registered (`prunable`) and `git worktree add` then fails with `is a missing but already registered worktree` until `git worktree prune`; and `git worktree add -b <b> <path> origin/main` sets the upstream to `origin/main` unless `--no-track` is given.
- **E6 (run in prep: see the Verification log for the latest run)**: can the designed tooling satisfy the sequestered spec, and does the spec catch wrong implementations? A throwaway prototype (reverted, never committed) is run against the spec, the full gate, and planted mistakes; the result and the mistakes are recorded in the Verification log.
- **E7 (run in prep: PASS)**: two branches that each add `tracker/issues/c0420/` with different slugs squash-merge with no conflict (the template's `check.sh` is identical, the docs are differently named), leaving one directory with two docs. That is why `store.find` must error on it.

## Regression guard
- **c0010's sequestered `tracker-lifecycle.spec.luau`** (`tests/acceptance/c0010/`): its clone has no remote, so `refuseInMainCheckout` never fires, and it runs `start` on `main` (the unchanged `switch -c` path). It must stay green.
- **Existing specs**: `tests/tooling/*` and `tests/meta` are unchanged. Any spec that runs `new`, `renumber` or `start` in a clone that has an `origin` must remove it or run in a worktree; the run of the full gate in E6 shows none does.
- **Every later raft's gate** runs this issue's promoted spec, so the spec must not depend on the branch or detached state of the checkout it runs from (design-review-001 F1: the fixture pins its own `main`).

## Test plan
`acceptance/worktree.spec.luau` sets up a scratch `.cache/wt-e2e/`:
- a bare `origin.git`, cloned from the repo's committed HEAD, **with `main` forced as the fixture's branch** and the seed's own `origin` remote removed (so the seed can run `new`), with the working-tree `scripts/`, `tracker/templates/` and `.gitignore` overlaid and committed;
- a clone `main/` of that bare repo, with an empty tracker and four ready fixture rafts, `R0010` (`demo`) to `R0040` (`fourth`), each with one issue `f0010` to `f0040`;
- the clone's origin is the local bare repo, so pushes are real and `gh` is never called, except in the GitHub case, which puts a fake `gh` first on `PATH` (with `GIT_TERMINAL_PROMPT=0`).

Cases (`spec case → AC`):
- `worktree creates a raft-named worktree and branch from origin/main` → AC1 (also asserts the new branch has no upstream)
- `worktree is idempotent and works from inside another worktree` → AC1
- `main checkout stays on main and clean` → AC1
- `start and new are refused in the main checkout` → AC6
- `worktree resumes an existing branch after its worktree is deleted` → AC1
- `worktree refuses a branch checked out elsewhere` → AC1
- `start inside the worktree reuses the branch and pushes` → AC2 (also asserts one commit on top of `origin/main`)
- `non-GitHub origin skips the draft PR` → AC2
- `GitHub origin opens the draft PR` → AC2: origin's fetch URL is `https://github.com/x/y.git` and its pushurl is the bare repo, and a fake `gh` records its argv; the case asserts `pr create` and `--draft` were passed.
- `worktree branches from the fresh origin/main, not the invoking tree` → AC1: origin is advanced from a separate clone; `worktree <name>` run from inside a worktree that has its own commits must land on `git ls-remote origin main`, not on the invoking tree's HEAD or the main checkout's stale `main`.
- `worktree creates a named worktree from origin/main` → AC6
- `new issue works in a named worktree` → AC6
- `worktree recreates a worktree whose directory was deleted` → AC6
- `worktree rejects bad names and non-raft ids` → AC6
- `worktree-prune removes squash-merged done rafts and keeps unfinished ones` → AC3
- `worktree-prune keeps a raft that is done only on its own unmerged branch` → AC3
- `worktree-prune lists a named worktree and leaves it` → AC3
- `worktree-prune never forces: a dirty finished worktree survives and the exit code is 1` → AC3
- `worktree-prune run from inside a finished worktree skips it` → AC3
- `worktree refuses a done raft` → AC6
- `duplicate ids are reported` → AC7: a second `<id>-*.md` in an item directory, and the same id in `issues/` and `issues/active/`, each make `find` and `list` fail naming the id.
- `post-edit hook lints with the edited file's worktree config` → AC4
- `post-edit hook ignores a file outside any repository` → AC4
- `stop hook gates the session's cwd worktree` → AC4
- `stop hook gates the worktree root when cwd is a subdirectory` → AC4

`check.sh` runs the spec **once** per check into a variable, fails a check if the spec did not load (`could not load spec`), requires each named case to exist in the spec source (the runner prints no per-case PASS lines) and not appear in a FAIL line, and then requires the summary to show no failures.

## Acceptance criteria

### Checked
- **AC1**: `tracker.sh worktree <R>` creates, or reuses, `.worktrees/<R-id>-<slug>` on branch `<R-id>-<slug>` from a freshly fetched origin/main, with no upstream. It prints only the absolute path, never moves the main checkout, resumes from an existing branch, refuses a branch checked out elsewhere, and `.worktrees/` never shows up in the main checkout's `git status`.
- **AC2**: `start` inside that worktree reuses the branch, commits once, and pushes. It opens a draft PR for GitHub origins (`gh pr create --draft`) and skips it, with a message, for others.
- **AC3**: `worktree-prune` removes the worktree and branch of every raft that is in `done/` on the base branch, including after a squash merge. It keeps everything else: unfinished rafts, freshly created worktrees, a raft done only on its own unmerged branch, a dirty worktree (exit 1, never `--force`), the worktree it runs in, and named worktrees (listed).
- **AC4**: The hooks act on the tree of the edited file (post-edit) or the session's `cwd`, or its repo root when `cwd` is a subdirectory (stop), not on the tree the hook script lives in.
- **AC5**: The skills, prompt template, settings and AGENTS.md carry the worktree rule: the named files contain `scripts/tracker.sh worktree`, the tracker skill has "Worktrees" and "Landing a change" sections, the settings allow the two new commands, and none of the skills or the template contains the old instructions to switch to, commit on, or diff against `main` in the main checkout (the negative grep in `check.sh`).
- **AC6**: `tracker.sh worktree <name>` creates, or reuses, `.worktrees/<name>` on branch `<name>` from origin/main for a valid plain name, recreates one whose directory was deleted, and rejects invalid names, item ids that aren't rafts, and done rafts, creating nothing. `new issue` works inside such a worktree, and `new` and `start` are refused in the main checkout of a repo with an origin.
- **AC7**: An item id that appears twice (two documents in one item directory, or the same id in two state directories) makes `find` and `list` fail naming the id.

### Judged
- **JC1: the skills leave no path that mutates the main checkout.**
  - **Pass**: in each of execute-raft, make-issue, ticket-prep, make-prompt, review, tracker, the prompt template, AGENTS.md and SETUP.md, every instruction that runs in the main checkout is on the whitelist in the worktree rule (rule 1), and every instruction that edits, stages, commits, switches branches or runs a gate does so in a worktree. The landing procedure is stated once (tracker skill) and referenced, not contradicted, elsewhere.
  - **Fail**: any main-checkout command that isn't on the whitelist, any instruction to commit, switch or edit on `main`, or two documents that disagree about the procedure. Quote each offending line.

### Observed
None.

## Implementation steps
1. `.gitignore`, `raftBranch`, `mainRoot`, `onGitHub`, `refuseInMainCheckout`; use them in `start` and `done`, and guard `new`, `renumber` and `prompt`. Commit.
2. `store.find`'s duplicate error. `cmd.worktree` (raft and named targets) and `cmd["worktree-prune"]`, plus USAGE. Commit.
3. Hooks and `.claude/settings.json`. Commit.
4. Docs: AGENTS.md, the six skills, the prompt template, SETUP.md. Commit.
5. Run `scripts/tracker.sh check c0041` and `promote-check R0020`. Optionally record E4.

## Verification log

- **E6 prep run (2026-09-30), the throwaway prototype (reverted, never committed):** about 200 lines across `scripts/tracker/main.luau`, `scripts/tracker/store.luau`, both hooks and `.gitignore`.
  - All 25 spec cases pass, run from a feature branch (not `main`), and `scripts/check.sh --full` passes with the prototype in place: 328 specs, including c0010's lifecycle spec.
  - Ten planted mistakes each fail the case written to catch them (some also cascade into later cases that share fixture state): prune passing `--force`; "finished" judged on the worktree's own branch instead of the base; `onGitHub()` always false; the stop hook using `cwd` without `rev-parse --show-toplevel`; branching from `HEAD` instead of `origin/main`; never fetching; not pruning stale registrations first; no `--no-track`; `start` not refusing in the main checkout; no duplicate-id detection.
  - Two prototype-only fixes worth knowing: the worktree-list parser needed a non-optional accumulator to pass strict type checking, and the spec's seed clone must drop its `origin` remote so it can run `new` (which is refused in a main checkout that has one).
- **E5 and E7 prep runs (2026-09-30):** re-verified in a scratch repo on git 2.54: the default upstream of `worktree add -b b p origin/main` is `origin/main` and `--no-track` removes it; a deleted worktree directory stays `prunable` and `worktree add` refuses until `git worktree prune`; two branches adding `c0420` with different doc slugs squash-merge with exit 0 into one directory holding two docs.


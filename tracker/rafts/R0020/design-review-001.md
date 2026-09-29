# Review 001: R0020 (design mode)
Inputs: main @ b671ff3 — R0020 doc + check.sh; c0041 doc, check.sh, acceptance/worktree.spec.luau; scripts/tracker/main.luau, store.luau, scripts/lib/{sh.luau,ac.sh}, scripts/hooks/*.sh, scripts/check.sh, tests/run.luau, .gitignore, .claude/settings.json, tracker/templates/prompt.md, SETUP.md, skills (review, tracker, testing, execute-raft, ticket-prep); origin/R0010-foundation @ 9f451ba (c0010 tracker-lifecycle.spec.luau and its tracker tree). I ran scratch experiments under .cache/rev1 and .cache/rev2, plus `tracker.sh check c0041` (0/6: fails at "usage" because `worktree` doesn't exist, so for the right reason on `main`) and `promote-check R0020` (OK).

### F1 [high] The spec fixture copies whatever branch the root checkout is on, so the spec can pass only when root is on a branch literally named `main`
Where: worktree.spec.luau, first case (`git clone -q root seed`, then `--bare seed origin`, then `clone origin main`)
Evidence: a local `git clone` checks out the source's current branch and creates only that local branch. A `--bare` clone copies only `refs/heads/*`. Experiment (.cache/rev1): source on `R0020-feat` gives `git clone src c1`, and `c1` is on `R0020-feat`. From the bare clone, `c2` is on `R0020-feat` too, with `origin/HEAD -> origin/R0020-feat`. So when the check runs on the raft branch `R0020-worktrees-by-default` (execute-raft Phase 3, `done`'s RC0), the fixture's origin has no `main`. `worktree R0010` has no `origin/main` or `main` to branch from, and "main checkout stays on main" expects `main` but gets `R0020-worktrees-by-default`.
- On a CI `pull_request` run (detached merge ref), the clone is detached with no branch at all. Checked: `c4` gives `* (no branch)`.
- Once promoted into `tests/acceptance/`, this spec runs in every future raft's `scripts/check.sh --full` from its `.worktrees/<R>` branch. So every later raft's RC0 fails.
- The executor can't fix any of this, because the spec is sequestered.

Fix: in the first case, right after cloning `seed`, add `git(seed, { "checkout", "-q", "-B", "main" })` so the fixture commit and the bare repo's HEAD are `main`. Re-run the check from a non-`main` branch in prep to prove it.

### F2 [high] c0041 collides with R0010's emergent c0041 on origin/R0010-foundation
Where: tracker/issues/c0041 (main) vs. `tracker/issues/active/c0041/c0041-check-affected-empty-array-bash32.md` (origin/R0010-foundation @ 2d47dbf); R0020 doc "Order & dependencies"
Evidence: `store.find` returns the first directory in STATE_ORDER and ignores the rest. `store.all` calls `find(name)`, so after both branches merge, one c0041 shadows the other:
- `members R0020` / `members R0010` return the wrong item or a duplicate;
- `check c0041` runs the wrong check.sh;
- R0020's `done` may promote or move the wrong issue.

The raft doc says the only merge overlap is SETUP.md, so this goes unnoticed until it bites. Ids come from `nextNumber` on each branch, so this design (whose goal is parallel rafts) will produce more of these collisions.

Fix: renumber now, before execution (`scripts/tracker.sh renumber c0041 c0050`, updating the R0020 doc and check paths), and list the collision risk in "Order & dependencies". Optionally add one line to the tracker skill: emergent issues in a worktree must renumber on rebase if their id exists on `origin/main`.

### F3 [high] AC2's "PR only for GitHub origins" is tested only in the negative, so an implementation that never opens a PR passes
Where: c0041 AC2; spec case "non-GitHub origin skips the draft PR"
Evidence: the only assertion is that the skip message is printed for a local bare origin. An `onGitHub()` that always returns false, or a `start` that drops `gh pr create`, passes AC2 and breaks every real raft's draft PR. `done`'s `hasUpstream() and onGitHub()` gating is untested as well.

Fix: add a case that points origin's fetch URL at `https://github.com/x/y.git` and `remote.origin.pushurl` at the bare repo (so `get-url` says GitHub but pushes stay local). Put a fake `gh` first on `PATH` via `process.exec`'s `env` so it records its argv, then assert `pr create --draft` was invoked.

### F4 [high] AC3 can't tell "done on the base branch" from "done on the worktree's own branch"
Where: spec case "worktree-prune removes squash-merged done rafts…"; Design `worktree-prune` step 2
Evidence: wt1's raft is moved to `done/` on its branch **and** squash-merged before prune runs. So an implementation that tests `tracker/rafts/done/<R>` in the worktree's HEAD (or its working tree) removes wt1, keeps wt2 (backlog everywhere), and passes. In real use, that implementation removes the worktree and `-D`s the local branch as soon as `tracker.sh done` runs, before the human has merged the PR, which is the window when review fixes still land.

Fix: give the spec a third raft (or re-use R0020-other) that is moved to `done/` and pushed on its branch but **not** merged, and assert that prune keeps its worktree and branch.

### F5 [medium] Prune's "never `--force`" safety and its exit status are unspecified or untested
Where: Design `worktree-prune` steps 4–5; AC3
Evidence: `git worktree remove` refuses a worktree with modified or untracked files (verified: rc=128, "contains modified or untracked files, use --force"). It deletes ignored files like `.cache/` silently (verified: rc=0). No case makes a finished worktree dirty, so an implementation that passes `--force` (destroying uncommitted work) passes AC3. The design also doesn't say whether prune exits 0 or 1 after "report and continue".

Fix: add a case with a finished-and-merged raft whose worktree has an untracked file. Assert the worktree and branch survive and stderr names it, and state the exit code (suggest 1 if anything was skipped).

### F6 [medium] check.sh AC1–AC4 report PASS when the spec fails to load
Where: c0041/check.sh `cases_pass`
Evidence: tests/run.luau prints `FAIL <file>: could not load spec: …`, with no ` :: `, then `0 passed, 1 failed, 1 spec files`. `cases_pass` only rejects FAIL lines containing `:: <case>`, and the summary regex accepts any counts, so all four per-AC checks print PASS. Only the final "AC1-AC4: every case" line fails. The overall gate still fails, but `done`'s log, the reviewer and the executor's triage see "AC1..AC4 PASS". The same happens if a case name is renamed or dropped. The spec also runs 5 times per check.

Fix: in `cases_pass`, add `grep -q "could not load spec" <<<"$out" && { echo "$out"; return 1; }`, and require each named case to be absent from FAIL lines **and** `failed` < total. Better: run the spec once into a variable and grep it per AC.

### F7 [medium] The Stop hook's `cwd`, and the persistent `cd` the workflow relies on, are unproven Claude Code behaviour with no experiment
Where: Design `stop.sh`; Docs (execute-raft step 2, prompt rule 2); Unknowns (only E1–E3)
Evidence: Claude Code documents `cwd` as a common hook-input field. Nothing in prep shows that it follows the Bash tool's `cd` into `.worktrees/<R>`. Also, whole workflow assumes one `cd` persists for the rest of the session:
- Subagent Bash calls reset cwd every call.
- `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR` resets it too.

If it doesn't persist:
- later `tracker.sh commit` calls run in the main checkout (they fail only by luck, via `activeRaft`);
- Edit/Write with relative reasoning land in the main checkout;
- the Stop gate checks `main`.

Fix: add E4 with this pass/fail question: "In a session started in the main checkout, after `cd .worktrees/X`, does the Stop hook input's `cwd` equal `.worktrees/X`?" (Log stdin from a throwaway hook.) Fallback, arguably the better primary path: have the human launch the executor **inside** the worktree (`cd "$(scripts/tracker.sh worktree R)" && claude`). Then `$CLAUDE_PROJECT_DIR` is the worktree, the hooks are already right, and nothing depends on `cd` persisting. Document which one applies.

### F8 [medium] Hook edge cases: a subdirectory `cwd` isn't tested, and the `cd "$(…)" || exit 0` idiom doesn't fail
Where: Design `post-edit.sh` / `stop.sh`; spec cases for AC4
Evidence:
- The stop case passes `cwd` = the worktree root. So `cd "$cwd"` without `rev-parse --show-toplevel` passes, yet sessions routinely sit in `src/…`. From there, `scripts/check.sh` isn't found (the hook exits 2 with a bogus error), and `git ls-files --others` prints cwd-relative paths that the `^(src|tests)/` filter misses.
- `cd ""` succeeds on macOS bash 3.2 (verified: rc=0, stays put). So the design's "run `cd "$(git … rev-parse --show-toplevel)"` and exit 0 if that fails" never exits for a file outside any repo; it lints from wherever the hook happens to be.

Fix: add a stop case with `cwd = wt2/src/shared`. In the design, spell it `top=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null) || exit 0; cd "$top"` (and use the same pattern for `cwd` with its fallback).

### F9 [medium] `worktree-prune` run from inside a worktree it removes breaks halfway
Where: Design `worktree-prune`; execute-raft doc "After the human merges: `scripts/tracker.sh worktree-prune` from any checkout"
Evidence: `scripts/tracker.sh` `cd`s to the invoking worktree's root. `git worktree remove <self>` succeeds (verified rc=0, directory gone), and every later `git` spawn (`branch -D`, the next worktree) then runs with a deleted cwd and fails. The executor is exactly the agent sitting in that worktree when it prunes.

Fix: run prune's git commands with `-C mainRoot()` and skip (with a message) the worktree that contains the current toplevel. Alternatively, have the docs say to run prune from the main checkout only.

### F10 [medium] AC1 covers only the "new branch" and "already registered" paths
Where: Design `cmd.worktree` step 4, second bullet; AC1
Evidence: the "branch exists locally or only on origin" path (resume on another host, or after the worktree was deleted) has no case. An implementation that always does `worktree add -b` fails there with "a branch named … already exists", and still passes. "Branch already checked out in another worktree" (today's state: `R0010-foundation` checked out in the main `pickman` checkout) makes `git worktree add` fail, and the design doesn't say what to print.

Fix: after the start/push case, `git worktree remove wt1` + `git branch -D R0010-demo`, then run `worktree R0010` and assert the path, the branch, and HEAD == `origin/R0010-demo`. In the design, say that "checked out elsewhere" prints that path to stderr and exits 1.

### F11 [medium] The docs never say where R0020 itself is executed
Where: R0020 "Risks & rollback"; execute-raft as it stands at execution time
Evidence: `pickman` is occupied by R0010 (on `R0010-foundation`), and `pickman.main` is the only checkout on `main`. The risk section forbids `.worktrees/` inside a main checkout until R0010 is done. The inlined execute-raft skill still says to run `start` in the current checkout, so a context-free executor will run `start R0020` in `pickman.main` and move it off `main`, which is the exact failure c0041 fixes.

Fix: add one line to the raft doc: "Execute in a sibling worktree: `git worktree add -b R0020-worktrees-by-default ../pickman.R0020 origin/main && cd ../pickman.R0020 && scripts/tracker.sh start R0020`." The new "branch already current" path in `start` then dogfoods itself; note that it needs step 1 committed first, or keep today's `start`.

### F12 [low] A new worktree tracks `origin/main`
Where: Design `cmd.worktree` step 4, third bullet
Evidence: `git worktree add -b R9-x <path> origin/main` sets `@{u}` = `origin/main` (verified). Until `start`'s `push -u` fixes it, `hasUpstream()` is true, `git status` says "up to date with 'origin/main'", and a bare `git push` would target the wrong ref.

Fix: add `--no-track`.

### F13 [low] Weak spots in the spec and check
Where: spec and check.sh
Evidence:
- AC2 says "commits once", but nothing asserts `HEAD~1 == origin/main`.
- "done rafts are refused" is untested.
- AC5's `^#* *worktrees` also matches any line that starts with "worktrees".
- The hook JSON cases don't include a path with a space. Real `pickman` paths have none, but `sed '[^"]*'` handles spaces while `\"`/`\\` in paths degrade to the fallback silently.

Fix: add the one-line asserts. Use `^#+ *Worktrees` for AC5.

### F14 [low] The settings allowlist and "Touched modules" leave out the new commands
Where: .claude/settings.json; c0041 "Touched modules"
Evidence: `scripts/tracker.sh worktree` and `worktree-prune` aren't in `permissions.allow`, so an autonomous executor may be blocked on its very first command.

Fix: add `Bash(scripts/tracker.sh worktree:*)` and `Bash(scripts/tracker.sh worktree-prune:*)`, and list `.claude/settings.json` under Touched modules.

Verdict: changes

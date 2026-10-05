# Review 002: R0002 (design mode)
Inputs: prep-c0005-scope @ bf7a8b2: R0002 doc + check.sh; c0005 doc, check.sh, acceptance/worktree.spec.luau; design-review-001.md, design-refute-001.md; skills (review, tracker, execute-raft, make-issue, ticket-prep, make-prompt, testing, architecture, metrics), AGENTS.md, SETUP.md, tracker/templates/{prompt.md,issue/check.sh}, scripts/tracker/{main,store}.luau, scripts/tracker.sh, scripts/hooks/*.sh, scripts/lib/ac.sh, scripts/check.sh, scripts/affected.luau, scripts/ci-verify.sh, tests/run.luau, .github/workflows/check.yml, .claude/settings.json, .gitignore. Scratch git experiments ran outside the repo, under the session scratchpad.
Dropped from design-review-001: F1–F10. I checked each against the spec, check.sh and design, and each is really fixed: `checkout -B main` at spec:113; the fake-`gh` GitHub case at spec:210; the R0003 unmerged-done case at spec:251/265; the dirty case with exit 1 at spec:277; check.sh loads the spec once and fails on `could not load spec`; E4 plus launch-inside (rule 4); the subdirectory-cwd and outside-repo hook cases; prune from inside at spec:290; resume and refuse at spec:177/187. design-refute-001 answers only F1–F10. F11–F14 of review-001 have no answer, so they are repeated below where they still apply (ticket-prep step 5.3 requires every finding to be answered).

### F1 [high] AC1/AC6 "from origin/main" passes an implementation that branches from the invoking tree's HEAD, or that never fetches
Where: worktree.spec.luau cases at :105, :165 and :230; c0005 Design `cmd.worktree` steps 3 and 5 (line 76)
Evidence: in the fixture, `origin/main` only ever moves through `squashMerge` (spec:96-100). That helper commits in the main checkout and pushes from it, so the main checkout's `HEAD`, its local `main` and its `origin/main` are always the same commit. Its push also updates `origin/main` without a fetch. `wt1` is the tree that "works from inside another worktree" invokes from, and it has no commits yet at that point (spec:168), so its HEAD is also `origin/main`. The same holds for the named case (spec:230), which runs from `main` before any squash. So both `git worktree add -b <b> <path> HEAD` and an implementation that skips `git fetch` pass every AC1 and AC6 case. In real use, that implementation has two effects:
- `tracker.sh worktree capture-x` run from inside a raft worktree branches the capture from the raft branch, and the capture PR then carries the raft's commits.
- Run from a main checkout that hasn't been pulled, it branches from stale `main`, which widens the ID-collision window (F2).
Fix: add a case that first advances `origin` from a separate clone (`git clone origin other`, commit, push). Then run `worktree <name>` from inside a worktree that has its own commits (for example wt2 after `start`). Assert that the new HEAD equals `git ls-remote origin refs/heads/main` and does not equal the invoking tree's HEAD or the main checkout's `main`.

### F2 [high] Concurrent captures and preps that pick the same ID merge silently, and one item disappears
Where: c0005 Usability ("`tracker.sh renumber` on rebase already covers that"); R0002 Risks ("two unmerged worktrees pick the same issue number"); landing procedure step 3
Evidence: the worktree rule makes captures and preps concurrent: each is branched from `origin/main` and picks `nextNumber` independently. The issue `check.sh` template substitutes only `{{ID}}`, so two captures of `c0044` produce byte-identical `check.sh` files and differently named docs. Experiment (scratch repo): branch A adds `tracker/issues/c0044/{check.sh,c0044-foo.md}` and branch B adds `{check.sh,c0044-bar.md}`. `merge --squash` of A and then B exits 0 with no conflict, and `c0044/` then holds both `c0044-bar.md` and `c0044-foo.md`. `store.find` → `docIn` returns whichever doc `readDir` yields first, so the other issue becomes invisible to `list`, `members` and `prompt`. GitHub reports `MERGEABLE`/`CLEAN`, so the Merging conditions pass. `R` ids from `new raft` behave the same way. The "Conflicts" rule assumes someone notices the collision, but nothing detects it, and before this design captures were serial on `main`.
Fix: make it detectable and make detection part of landing.
- `store.find` errors when an item directory holds more than one `<ID>-*.md`, or the same ID exists in two state directories. That turns `list`, `check` and the gate's tracker usage red.
- Add landing step 3.0: `git fetch && git merge origin/main`, run the gate, and `renumber` on any duplicate before merging.
- Add a spec case that seeds a duplicate and asserts the error.

### F3 [high] The documented ticket-prep target `prep-<R-id>` is rejected by the designed name rule, and for a new raft it can't be known in advance
Where: c0005 line 31 (`prep-R0006` as an example), line 49 (rule-2 table), line 107 (ticket-prep Docs), line 68 (Classify: `^[a-z][a-z0-9-]*$`, "uppercase → invalid worktree name"); spec:240 pins `UPPER` as rejected
Evidence: `prep-R0006` contains `R`, so it matches none of the three classes and fails with `invalid worktree name`. The sequestered spec forbids relaxing the rule, so the executor will write a ticket-prep step whose first command always fails. Separately, ticket-prep step 1 allocates the raft ID with `tracker.sh new raft`, which (under the rule) must run inside the prep worktree. So the name `prep-<R-id>` can't be chosen before the worktree exists, and an ID picked there can still change on renumber (F2).
Fix: name prep worktrees `prep-<slug>` (the raft slug, lowercase), or lowercase the id (`prep-r0060`). Update lines 31, 49 and 107.

### F4 [medium] A registered worktree whose directory is gone makes `worktree` print a path that doesn't exist, and resume fails
Where: c0005 line 73 ("The path is already a registered worktree: print the path, exit 0"); `worktree-prune`
Evidence: scratch experiment on git 2.54. After `rm -rf .worktrees/R0001-x`, `git worktree list --porcelain` still lists the path, with `prunable gitdir file points to non-existent location`. The design's first case matches it and prints the path, so `cd "$(scripts/tracker.sh worktree R0001)"` fails. Skipping that case doesn't help either: `git worktree add .worktrees/R0001-x R0001-x` fails with `is a missing but already registered worktree`, exit 128. The same stale entry also makes the branch look "checked out elsewhere". Losing a directory this way is plausible on this host (iCloud history; manual cleanup).
Fix: run `git -C mainRoot() worktree prune` at the start of `worktree` and of `worktree-prune`, or treat `prunable` entries as absent. Add a spec case: `rm -rf` a worktree dir, then `worktree R…` recreates it.

### F5 [medium] AC5's negative grep and the Docs list miss existing instructions that still mutate or contradict the landing procedure
Where: check.sh AC5 `bad=$(grep -rnF …)`; c0005 Docs list (lines 103-111)
Evidence: running the grep today hits exactly the five lines the design plans to change. The following survive it:
- `ticket-prep/SKILL.md:61`: "**Commit** the prepared tracker items … to main as one commit". Only line 62 ("straight to main") is caught, so deleting 62 passes AC5.
- `tracker/SKILL.md:8`: "don't commit tracked work with a plain `git commit`". This directly contradicts landing step 1 ("plain `git add` and `git commit` for capture, prep …"), and the Docs list doesn't mention it.
- `tracker/SKILL.md:63`: "if the root is on another branch (in-progress work there): `git -C <root> fetch origin main:main`". This legitimizes a main checkout that isn't on `main`.
- `tracker/SKILL.md:66,68`: EnterWorktree/ExitWorktree. Claude Code's EnterWorktree creates worktrees under `.claude/worktrees/`, which is not gitignored (it makes the main checkout dirty) and which `worktree-prune` never sees. The design never says whether EnterWorktree is allowed.
- `SETUP.md:51`: "`tracker.sh start` fails on `gh pr create` … there must be an `origin` remote". This is stale once `start` skips non-GitHub origins.
- The grep is case-sensitive, and phrasing such as "commit … to main" or `git checkout main` is not covered.
Fix: add these lines to the Docs list explicitly: tracker line 8 becomes "…except capture/prep/doc worktrees, per Landing a change"; "After merge" is replaced by landing step 4; EnterWorktree is either forbidden or given its path. Extend the grep with `-i` and add `-e "to main as one commit" -e "root is on another branch" -e "EnterWorktree"`. Keep JC1 as the backstop.

### F6 [medium] `git diff main...HEAD` (reviewer input) now diffs against a stale local `main`
Where: execute-raft Phase 4 step 2 (`git diff main...HEAD`), review skill code mode Inputs; the Docs list doesn't mention them
Evidence: today Phase 0 runs `git switch main && git pull`, so the executor's local `main` is current. Under the rule, the worktree branches from `origin/main` and nobody updates the local `main` ref before execution; it only moves when the main checkout is pulled after some landing. If the main checkout is behind, `merge-base(main, HEAD)` is the old `main`. The reviewer's diff then includes every commit merged by others between the two, which is unrelated code handed to the adversarial reviewer as "the PR".
Fix: in both skills, use `git fetch origin main && git diff origin/main...HEAD`, and add those two skills' lines to the Docs list.

### F7 [medium] make-prompt still creates and commits a placeholder raft in the main checkout
Where: make-prompt SKILL.md:8 and :16; `cmd.prompt` (main.luau:505-510 calls `cmd.new`); c0005 line 108 ("readiness is checked in a read-only way from the main checkout")
Evidence: `tracker.sh prompt <issue>` for a raftless issue writes `tracker/rafts/R…/` in the tree it runs in, which under the design is the main checkout. Step 16 then tells the agent to commit and push it. AC5's grep forces the executor to reword "direct commits to main", but the design gives no replacement, so the only mutation path through make-prompt stays open.
Fix: make-prompt refuses a raftless issue ("run ticket-prep; it always creates a raft, `--single` for one issue"), and the Docs line for make-prompt says so. Optionally have `cmd.prompt` fail instead of creating the raft when run in `mainRoot()`.

### F8 [medium] JC1's rubric can't pass as written, because the documents it rules on must run things in the main checkout that rule 1 doesn't list
Where: c0005 JC1 Pass ("every instruction that … runs a gate does so in a worktree; the only main-checkout commands are the read-only and `pull --ff-only` ones listed in the worktree rule"); rule 1 (line 42)
Evidence: these instructions necessarily run in the main checkout, yet none is in rule 1's list:
- SETUP.md's bootstrap, `git clone … && cd pickman && scripts/setup.sh`, ends with `scripts/check.sh --full`, which runs the gate there.
- `scripts/tracker.sh worktree` itself runs `git fetch` and `git branch --track` (branch creation).
- make-prompt runs `tracker.sh prompt`.
- `tracker.sh worktree-prune`.

A strict reviewer fails SETUP.md; a lenient one approves anything. Neither ruling is decidable from the rubric.
Fix: make rule 1 an explicit, complete whitelist: `git fetch`, `git pull --ff-only`, `scripts/setup.sh` (first-time bootstrap only), `scripts/tracker.sh worktree|worktree-prune|list|find|prompt <R-id>`, `git worktree …`, `git branch -D <merged>`, and read-only inspection. Then write JC1 as "every main-checkout command in the named documents is on rule 1's whitelist; quote any that isn't".

### F9 [medium] Landing step 4 removes the agent's own project directory when the agent was launched inside the worktree (rule 4's primary path)
Where: c0005 line 57 (landing step 4, four separate commands) and line 58 (rule 4)
Evidence: with `cd "$(scripts/tracker.sh worktree R…)" && claude`, the session cwd and `$CLAUDE_PROJECT_DIR` are the worktree. After `git -C <root> worktree remove <path>`, the Bash tool has no working directory to spawn in, so the separate `branch -D` and `worktree prune` calls that follow can't run. Every later hook invocation (`"$CLAUDE_PROJECT_DIR"/scripts/hooks/stop.sh`) also fails with "not found". The execute-raft note "post the report before cleanup" covers the report, but not the rest of cleanup.
Fix: specify step 4 as one chained command, run last: `git -C <root> pull --ff-only; git -C <root> worktree remove <path> && git -C <root> branch -D <branch>; git -C <root> worktree prune`. State that nothing follows it in the session. Alternatively, leave removal to a later `worktree-prune` run from the main checkout, which already skips the tree it runs in.

### F10 [medium] `start`, the command that caused the original incident, still switches branches in the main checkout with no guard
Where: c0005 line 86 ("Otherwise, behave exactly as today"); Non-goals ("Enforcing the rule mechanically")
Evidence: rule 4's fallback (agent started in the main checkout, `cd` first) and any subagent whose shell resets its cwd both run `scripts/tracker.sh start R…` from the main checkout. That relative path resolves to main's copy, and `tracker.sh` `cd`s to its own repo, so `git switch -c` moves the main checkout off `main`, which is exactly the Problem's first bullet. The non-goal is about a hook denying edits. A one-line precondition in `start` is not that, and it stays compatible with c0001's lifecycle spec (whose clone has no `origin`).
Fix: in `cmd.start`, if an `origin` remote exists, the current toplevel equals `mainRoot()`, and the branch is not already `raftBranch(raft)`, fail with `run start inside the raft's worktree: cd "$(scripts/tracker.sh worktree R…)"`. Add a spec case that runs `start` from the fixture's main checkout and asserts refusal, with main still on `main`.

### F11 [medium] (repeat of design-review-001 F11) Nothing says how R0002 itself is executed, and the prompt it gets still tells it to `start` in the current checkout
Where: R0002 doc (no execution note); make-prompt/template/execute-raft as they are on `main` at execution time
Evidence: the prompt for R0002 inlines today's execute-raft (Phase 0: `git switch main && git pull --ff-only`, then `start`), and the new launch line needs `tracker.sh worktree`, which doesn't exist until R0002 merges. `.worktrees/` isn't gitignored on `main` yet either, so a hand-made `.worktrees/R0002-…` makes the main checkout dirty. A context-free executor follows Phase 0 in whatever checkout it's in. design-refute-001 doesn't answer this finding.
Fix: add to the R0002 doc: "Bootstrap: execute in a sibling worktree, `git -C <root> worktree add -b R0002-worktrees-by-default ../pickman-R0002 origin/main`, launch the agent there, and run `start`, which will take the branch-already-current path once step 1 lands (or today's path if not)."

### F12 [low] (repeat of design-review-001 F12) New worktrees track `origin/main`
Where: c0005 line 76
Evidence: `worktree add -b <b> <path> origin/main` sets `@{u}=origin/main` (verified in review-001; unanswered). For named worktrees, nothing resets it until landing step 2's `push -u`, so a bare `git push` or `git status` compares against `main`.
Fix: `--no-track`.

### F13 [low] (repeat of design-review-001 F14) The permissions allowlist doesn't include the new first command
Where: .claude/settings.json; Touched modules
Evidence: `Bash(scripts/tracker.sh worktree:*)` and `worktree-prune` are missing, so the prompt's first action (`cd "$(scripts/tracker.sh worktree R…)"`) can block an autonomous executor on a permission prompt. Unanswered in design-refute-001.
Fix: add both entries and list `.claude/settings.json` under Touched modules.

### F14 [low] Spec and test-plan loose ends
Where: c0005 line 167; spec:197 and :210
Evidence:
- The Test plan says "two ready fixture rafts"; the spec builds four (R0001–R0004).
- AC2's "commits once" is still unasserted (repeat of review-001 F13): the `start` case never checks `HEAD~1 == origin/main`.
- The GitHub case points origin's fetch URL at `https://github.com/x/y.git`. Any `git fetch` that an implementation adds to `start` would reach the network or prompt for credentials, then hang or fail for a reason unrelated to the criterion.
Fix: correct the Test plan text; assert `git rev-parse HEAD~1` equals the fixture's `origin/main`; pass `GIT_TERMINAL_PROMPT=0` in that case's env.

Verdict: changes

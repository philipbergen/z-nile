# Review 003: R0020 (design mode)
Inputs: worktree prep-publish-state-to-main at a3ac240 plus uncommitted prep files: `tracker/rafts/R0020/{R0020.md,check.sh,design-review-001.md,design-refute-001.md,design-review-002.md,design-refute-002.md}`; `tracker/issues/c0053/{c0053.md,check.sh}`, `acceptance/{status,publish,commands}.spec.luau`, `replacements/c0005-worktree.spec.luau`, `experiments/{status.luau.txt,publish.luau.txt,prototype.patch}`; `scripts/tracker/main.luau`, `store.luau`, `scripts/tracker.sh`, `tests/run.luau`, `.github/workflows/check.yml`; the promoted specs that read touched files; review, tracker, testing and ticket-prep skills (worktree and `origin/main`); `origin/main` at 55e94b3. All runs were made in a scratch clone outside the repo with its own `.git` and its own bare origin (removed afterwards):
- Unpatched copy with the prep files: `tracker.sh check c0053` gives 1/8. AC4 passes; AC3 fails (1 passed, 21 failed); AC5-AC8 fail with their own messages. These are the right reasons.
- Prototype plus the c0005 replacement at a3ac240: the three c0053 specs give 45 passed, and `check.sh --full` gives 574 passed in 94 spec files. This reproduces E7.
- The same, merged with `origin/main` 55e94b3 (R0016): the patch merges cleanly, `check.sh --full` gives 604 passed in 99 spec files, and the c0053 specs give 45 passed.
- The same with `GIT_CEILING_DIRECTORIES=<root>/.cache`: 604 passed in 99 spec files, and the c0053 specs give 45 passed (see F3).

Dropped from review-002: F1 (renumbered; the base is stale again, see F2), F4, F5, F6, F7, F8, F9. Their fixes are in the documents and the prototype, and the spot checks hold.

The user decisions (the c0005 rewrite in prep, and three-word stamps) are not reopened. F1 and F2 are about how they were implemented.

### F1 [high] Every stamp the CLI writes is the same phrase, so the user's "identical concurrent moves conflict" decision is not implemented, and claim ownership is decided by a constant
Where: `prototype.patch` `stamp()` in main.luau: `math.randomseed(os.time() + math.floor(os.clock() * 1e6))`. c0053 The model ("Every published or carried write is a fresh stamp"). Test plan AC1 row, and the Rules row "Every write is a fresh `<state>-<three words>` stamp" (`reasoned`). `status.spec.luau`.
Evidence:
- In Luau, `os.clock()` is seconds since boot (`1933702.97` here), so the seed is about 1.9e12. `math.randomseed` saturates any seed of 2^31 or more: in Lune 0.10.5, seeds `2147483647`, `2147483648`, `1.9e12` and `1.9e12+7` all give the same draws `1 17 23`.
- 30 pairs of concurrent `lune` processes running the prototype's seeding and `status.stamp` gave `active-raging-silver-marble` 60 times out of 60, with different `os.clock` values each time.
- In the commands-spec fixture's origin, every first stamp from the CLI is `raging-silver-marble`: 154 `preparing-raging-silver-marble`, 142 `new-…`, 62 `active-…`. The only other phrase is the deterministic second draw (`plucky-raging-crimson`).
- Both worktrees' `.cache/tracker-claim-*` files contain `active-raging-silver-marble`. Review-002's own evidence shows `preparing-raging-silver-marble` too.

What this breaks:
- Two prep branches carrying `prepared` write the same line, and git merges them silently. This is exactly what the user's decision was meant to prevent.
- `start`'s ownership test (`raw == mine`) is true for any worktree that holds an old claim file for that raft. The file is never removed after a successful start or a give-back. A worktree that once started R0001 and gave it back (`status R0001 prepared`) therefore "resumes" another terminal's later claim: it skips the publish and creates a second branch and PR.

No spec can see any of this:
- `status.spec.luau` has no stamp case. The Test plan's `status :: a stamp is the state plus three words ...` and `two stamps made with different picks conflict ...` do not exist, and `status.stamp` and `status.phrase` are never called by a spec.
- The commands spec checks only the format (`^active%-%a+%-%a+%-%a+$`).
- The prototype *is* the "fixed suffix" mutant that the Rules row lists, and it passes.

Critique: the tempting fix is `math.randomseed(os.time())`. That stops the saturation, but two terminals started in the same second still write the same stamp.

Consequences: the entropy source has to differ between processes started together and fit in 31 bits. Ownership also depends on the stamp, so it inherits any weakness in that source.

Recommendation:
- Seed from a real entropy source, reduced into [0, 2^31). For example, read 4 bytes with `od -An -N4 -tu4 /dev/urandom` through `process.exec`, or fold `os.clock()` fractions together with `os.time()` modulo 2^31.
- Add the missing status cases:
  - `status :: a stamp is the state plus three words from the list, and parse/phrase read it back`;
  - `status :: two stamps made with different picks differ`.
- Add a commands case: the stub stamps of two `new issue` runs in **separate processes** (for example `c0001` and `c0210`) have different phrases. This kills the constant-seed mutant. A collision chance of 1 in 13,824 is acceptable.
- Remove `.cache/tracker-claim-<R>` when `start` finishes and when `status <R> prepared` gives the claim back. Add a case: a worktree whose earlier claim was given back is refused when another terminal starts the raft.
- Change the Rules row to `run`.

### F2 [high] AC5's `check.yml` change breaks the promoted c0015 spec, which no override names; the prep is again behind `origin/main`, whose skills now require an `Overrides:` line
Where: c0053 CI section, AC5, Implementation step 6, Regression guard (no `Overrides:` line), and E7 ("c0045 and the others pass unchanged"). `tests/acceptance/c0015/workflow.spec.luau:118`. On `origin/main` 55e94b3 (R0016): ticket-prep "Override check" and review Design mode item 4.
Evidence:
- `tests/acceptance/c0015/workflow.spec.luau:118` asserts `t.expect(on.push).toEqual({ branches = { "main" } })`. In the scratch prototype I added the designed `paths-ignore: ['tracker/**']` under `on.push`. The c0015, c0001 and c0003 workflow specs then gave `22 passed, 1 failed`: `FAIL c0015/workflow.spec.luau :: the workflow's triggers and the gate job are unchanged ...`. The executor may not edit that spec, so AC5 and RC0 cannot both pass. This is a guaranteed stop condition.
- E7 missed it because the prototype contains no `check.yml` change, and no skill changes either.
- Seven promoted specs read skill text as plain strings, and c0053 rewrites parts of those skills without a prototype: c0003/pipeline (tracker `## Merging`), c0043/{review-skill, format, ticket-prep}, c0047/override-check, c0048/board-docs and c0050/start-depends.
- `origin/main` moved to 55e94b3 after the round-2 renumber. It adds an `Overrides:` placeholder to the issue template and makes "an unnamed override, a missing line or an unfilled placeholder" a **high** in design review. c0053 has no `Overrides:` line, although it already rewrites `c0005/worktree.spec.luau` and now must also rewrite `c0015/workflow.spec.luau`.

Critique: the tempting fix is to let the executor "adjust" c0015. That breaks sequestration, which is why review-001 F1 led to `replacements/`.

Consequences: c0053 is a chore, so it may change promoted specs in its own raft (R0016's ticket-prep rule), but only if they are prepared and named now. Each new replacement needs an AC8 `cmp`. Skill edits that pinned specs read must keep the pinned phrases.

Recommendation:
- Merge `origin/main` (55e94b3) into the prep branch. With the prototype it passes 604 cases in 99 spec files; record that as E7.
- Add `replacements/c0015-workflow.spec.luau`, whose only change is `on.push` = `{ branches = { "main" }, ["paths-ignore"] = { "tracker/**" } }`. Extend AC8 to `cmp` it. Name both rewritten specs on an `Overrides:` line in Regression guard.
- Re-run E7 with the `check.yml` change applied.
- Either prototype the skill edits and run the seven skill-reading specs against them, or list those specs and their pinned phrases in Implementation step 7 as "keep verbatim".
- Fix the stale counts ("all 91 other spec files").

### F3 [high] The repo-root guard does not cover the incident it was added for, and c0053's own spec can push a real worktree's uncommitted work to its origin's `main` (repeat of review-002 F2)
Where: `publishing()` and `cmd.sync` in `prototype.patch` (the only callers of `guardRepoRoot`); R0020 Risks ("A tracker command runs in a directory that lost its `.git`"); E9; `commands.spec.luau` `elsewhere()` and `git()`; the c0005 replacement (`PICKMAN_PUBLISH=0`).
Evidence, from a scratch outer repository with a bare origin and a `.git`-less directory inside it holding the prototype's `scripts/`:
- `scripts/tracker.sh worktree zz` succeeded and registered `outer/repo/.worktree/zz [zz]` in the **enclosing** repository. That is the stray-worktree half of the incident E9 records. `worktree` never calls `publishing()`.
- `publishing()` calls the guard only when publishing is on. Under `PICKMAN_PUBLISH=0` every command skips it, and that is exactly how the c0005 replacement (the spec behind the incident) runs its fixtures. Unguarded commands that write include `worktree`, `start` (`switch -c`, branch push, `gh pr create`), `done`, `commit` and `worktree-prune`.
- The spec's own `elsewhere()` runs plain `git pull`, `add -A`, `commit` and `push origin HEAD:main` in `{base}/other`. I ran that sequence in `outer/repo/.cache/c0053-commands/other` with no `.git` there. It committed the outer worktree's uncommitted `wip.txt` as "other f0011" and pushed it to the outer origin's `main` (`b97ccd0 other f0011, wip.txt | 1 +`). In the real repository that origin is GitHub. The commands spec runs five times per gate (AC3, RC1, and RC2 three times). It deletes and rebuilds `{base}` at setup, so two overlapping runs in one worktree recreate the incident's window.

Critique: the tempting fix is to call `guardRepoRoot()` in more commands. That still leaves every raw `git` call in every spec, including this raft's own, falling through to the real repository.

Consequences:
- The cheap, general guard is git's own: `GIT_CEILING_DIRECTORIES=<root>/.cache` stops discovery from walking out of the fixture area. I ran the full gate with it (604 passed in 99 spec files) and the c0053 specs (45 passed), so no existing spec depends on the fall-through. `tests/run.luau` is not sequestered.
- The tracker guard should then key on "does this command write", not on "is publishing on".

Recommendation:
- `tests/run.luau` sets `process.env.GIT_CEILING_DIRECTORIES` to `<root>/.cache` before it loads specs. Add a tooling case: `git rev-parse` in a `.git`-less directory under `.cache` fails.
- `guardRepoRoot()` runs for every command except an explicit read-only list (`list`, `find`, `members`, `metrics`, `board`, `workstreams`, `promote-check`, `prompt`), whatever `PICKMAN_PUBLISH` says.
- Extend the lost-`.git` case to `worktree zz` (no worktree registered in the outer repository) and to `new issue` under `PICKMAN_PUBLISH=0`.
- Add Rules rows for both guards (mutants: ceiling removed; guard only when publishing). Correct R0020 Risks and E9 to match.

### F4 [medium] Preps already in flight when c0053 lands stay invisible: their raft ids and members can be taken again, and two worktrees hold R0018 today
Where: R0020 Risks (it covers only draft rafts already on `origin`, R0010-R0015) and Order & dependencies; c0053 Effective status (a member's `raft:` exists only on the prep branch).
Evidence: `git worktree list` shows `prep-beta-poll-transient-errors` and `prep-tracker-hardening` **both** holding `tracker/rafts/R0018` (`issues: [c0051]` and `issues: [c0055, …, c0630]`), and `prep-renumber-step-one` holding R0019 with c0052. On `origin/main`, c0052 has `raft: ` (empty) and `design: draft` and no `status:`, so after c0053 `tracker.sh status c0052` prints `new`. `new raft … c0052` then succeeds, and its id is allocated from origin plus the local tree, which in any other worktree does not contain R0018 or R0019. No command publishes a raft that exists only locally: `status <R-id> preparing` requires the document on origin.

Critique: the tempting fix is to publish the local raft from `status`. That is a new creation path through the publisher, with its own id-clash rules and spec cases.

Consequences: this is a one-time cutover, so a documented manual step decided with the user is cheaper than a tool path.

Recommendation:
- Add a cutover step to R0020 Order & dependencies and to the tracker skill's Sync and claim section, and confirm it with the user. Before c0053's PR merges, list the open `prep-*` worktrees and branches. Each one either lands first, or, after c0053 lands, runs `tracker.sh sync`, claims its members with `status <id> preparing`, and checks its raft id against `tracker.sh status`, renumbering (c0052) on a clash.
- Report the current R0018 double allocation to the user now.

### F5 [low] Claim rules that bypass their owners: `canClaim` stamps a lone issue of a draft raft, and `status <R> active` takes the `start` lock without `start`'s checks
Where: `status.canClaim(from, to, stored)` (no kind); `cmd.status` (allows `prepared>active`); `cmd.start` (local preconditions, including R0016's `depends_on` rule).
Evidence:
- `status f0020 preparing` on a member of draft R0010 is allowed (derived `preparing`, nothing stored), so it stamps the issue alone. A later `status R0010 preparing` then refuses with `f0020 is preparing on origin/main: cannot move to preparing`. The way out (`status f0020 new`, then claim the raft) is not documented.
- `status R0001 active` publishes `active` without the clean-tree, `design: ready` and `depends_on` checks, and without a claim file, so nobody can `start` the raft until someone moves it back. The commands spec uses this as a stand-in for a crashed start.

Recommendation:
- `canClaim` applies only to rafts (pass `isRaft`).
- `status` refuses `active` as a target ("only `start` claims active"). In the resume case, simulate the crash differently, for example with a `pre-push` hook on the raft branch push that fails after the claim.
- Spec cases for both.

### F6 [low] Smaller document inconsistencies
Where: `status.spec.luau` case "only preparing>prepared and active>done ride a pull request"; c0053 Test plan AC1 and AC2 rows.
Evidence:
- The status case's name and its `or (from == "active" and to == "done")` branch contradict "`done` is never a move target". The branch is dead because `active>done` is not in the table.
- The Test plan's AC2 row still names `an existing document may change its frontmatter, never its body`, but the spec's case is `an existing document may change its status: line and nothing else`.
Recommendation: rename the status case and drop its dead branch, and align the Test plan's case names with the specs. Do this together with F1's new stamp cases.

Verdict: changes

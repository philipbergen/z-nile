# Review 004: R0020 (design mode)
Inputs: worktree prep-publish-state-to-main at dce0940 (clean): `tracker/rafts/R0020/{R0020.md,check.sh,design-review-001..003.md,design-refute-001..003.md}`; `tracker/issues/c0053/{c0053.md,check.sh}`, `acceptance/{status,publish,commands}.spec.luau`, `replacements/{c0005-worktree,c0015-workflow}.spec.luau`, `experiments/{status.luau.txt,publish.luau.txt,prototype.patch,skills.patch}`; `scripts/tracker.sh`, `scripts/lib/{ac.sh,sh.luau}`, `scripts/tracker/main.luau`; the review, tracker, testing and ticket-prep skills; the other prep worktrees (`git worktree list`), and c0058 in `prep-check-isolation` plus its prototype `proto2-c0058` (read only).

All runs were made in scratch clones outside the repository, each with its own `.git` and its own bare origin (removed afterwards; the real repository and its worktrees were not touched):
- The prototype as instructed (both patches, both new modules, both replacements): `scripts/check.sh --full` gives 633 passed, 0 failed, in 103 spec files, and `scripts/tracker.sh check c0053` gives 8/8 PASS. This reproduces E7.
- The mutant "seed with `os.time()`" (the tempting fix that review-003 F1 named) gives 34 passed, 0 failed, on `status.spec` and `commands.spec` (F5).
- A cutover fixture: a prep raft that exists only locally, then `status c0001 preparing`, then `status R0001 prepared`, then the prep merged, then `start` (F1, F4).
- The c0053 specs under c0058's prototype fence, `proto2-c0058/scripts/lib/fence.sh` and `git-hooks/`: 21 passed, 16 failed (F2).
- A `.git`-less directory under an ignored `.cache/` inside an outer worktree with an origin: `worktree zz` and `prompt c0001` (F6).

Dropped from review-003: F1, F2, F3, F5 and F6. The fixes hold:
- Stamps now differ between processes.
- The c0015 replacement, AC8 and the `Overrides:` line are in place.
- The guard refuses `worktree zz` in a lost-`.git` directory, under `PICKMAN_PUBLISH=0` too.
- `canClaim` takes `viaRaft`.
- `status <id> active` is refused.
- The status case names are aligned.

F4 is repeated as F4 below.

The user decisions (prepared rewrites of promoted specs; a three-word stamp on every status write) are not reopened. F1, F4 and F5 are about how they were carried out.

### F1 [high] No skill ever runs the carried `status <R-id> prepared`, so every raft prepped under the new flow merges as `preparing` and can never be started or prompted
Where:
- `skills.patch`, ticket-prep: the hunk changes only section 1, and section 3 step 5 still says only "set `design: ready` on the raft and every member".
- The tracker skill's new Sync and claim section ("The move to `prepared` is **carried by the prep PR**", with no step or owner).
- c0053 Implementation step 7 ("ticket-prep ... sets `prepared`").
- `status.effective`: a stored field wins over the derived one.
- `cmd.start` requires `prepared` on origin.
- AC6.

Evidence:
- `new raft` stamps the raft and its members `preparing-<words>` on origin. After that, only `tracker.sh status <R-id> prepared` (carried) changes the line on the branch. The prototype's skill text never tells the prep agent to run it. The only place that runs it is the commands spec ("a prepared raft starts once": `trOk(cap, { "status", "R0001", "prepared" })`).
- With the line left as `preparing-…`, `status.effective` returns `preparing` although `design: ready`. So:
  - `start` refuses (`<id> is preparing on origin/main, not prepared`);
  - make-prompt's new precondition (`tracker.sh status <R-id>` prints `prepared`) fails.
- The only repair is a carried move, which needs a worktree and a second PR. In the main checkout `status` with a target refuses.
- I reproduced the end state in a scratch fixture. After the merged prep, `tracker.sh status` printed `c0001 preparing Alpha`, and `start R0001` failed with `c0001 is preparing on origin/main, not prepared` (exit 1).
- AC6 greps for `status <R-id> preparing` in the tracker skill only. A skill set that never carries `prepared` passes every check, and the prototype's skills are exactly that set.

Critique: the tempting fix is one sentence in ticket-prep step 5. The move is refused unless every local member is `preparing` on origin, so its place in the procedure matters. It must also come before the prep commit, or it is lost.

Consequences: `design: ready` and `status: prepared` now mean the same thing in two fields, and an agent can set one without the other.

Recommendation:
- ticket-prep section 3 step 5 becomes: "set `design: ready` on the raft and every member, then run `scripts/tracker.sh status <R-id> prepared` (carried: it edits the local documents), and only then make the prep commit." The tracker skill's Sync and claim section names this step.
- AC6 also requires `status <R-id> prepared` in ticket-prep.
- Optionally, `status <R-id> prepared` refuses unless the raft and its local members are `design: ready`, which ties the two fields together. Add a commands case for that refusal.

### F2 [high] c0058 (R0019, `prep-check-isolation`) and c0053 collide in code, not only in text: each blocks the other's sequestered specs
Where: R0020 Order & dependencies ("they overlap in intent but not in code"); c0053's `publish.luau` (`GIT_INDEX_FILE`), `commands.spec.luau` and `publish.spec.luau` (`GIT_CEILING_DIRECTORIES`, `unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE`, fixture `.git/hooks/pre-push`); c0058's design: the "Gate spec" item 4 and the "Ref guard" (`core.hooksPath` injected through `GIT_CONFIG_COUNT`).
Evidence:
- c0058's gate spec (`tests/tooling/repo-fence.spec.luau`) case 4 fails when any `.luau` or `.sh` file under `tests/`, `tracker/` or `scripts/` contains, among others:
  - `GIT_CEILING_DIRECTORIES`, `GIT_DIR` and `GIT_INDEX_FILE`;
  - `GIT_WORK_TREE`, `GIT_CONFIG_`, `hooksPath` and `env -u`.

  It exempts only c0058's own files. c0053 names these in:
  - `scripts/tracker/publish.luau` (the private index is the core of the design);
  - `commands.spec.luau` lines 21 and 81;
  - `publish.spec.luau` lines 20 and 40.
- c0058 sets `core.hooksPath` for every git a check runs, so a fixture's own `.git/hooks/pre-push` never fires. Its hooks do not chain to the repository's own hooks. Every lost-race case in c0053 depends on such a hook.
- I ran c0053's specs on the prototype inside `proto2-c0058`'s fence (`. scripts/lib/fence.sh && pickman_fence "$(pwd -P)" && lune run tests/run -- …publish.spec.luau …commands.spec.luau`). The result was 21 passed, 16 failed:
  - `commands :: an id taken by another terminal ...` got c0220, expected c0230;
  - `publish :: a lost race is retried ...` saw 1 build call, expected 2;
  - `publish :: gives up after ...`;
  - 13 commands cases that run after them in the shared fixture.
- Both sets of specs are sequestered. Whichever raft lands second hits a guaranteed stop condition: c0053's AC3, AC4, RC0 to RC2, or c0058's gate spec over c0053's promoted files.

Critique: the tempting fix is "whoever lands second resolves it", as R0020 says now. That is impossible without editing sequestered specs, and that is what the `replacements/` mechanism exists to avoid.

Consequences:
- If c0053 lands first, c0058 needs an exemption list that names c0053's publisher and specs, or a narrower rule ("no spec *sets* these for a git that runs in the checkout").
- If c0058 lands first, c0053's specs must drop the ceiling (c0058 provides it) and induce races without fixture hooks. For example, the race hook could be passed as `-c core.hooksPath=<fixture dir>` on the push. That is itself banned by c0058's `hooksPath` rule. So the two designs need a joint decision, which the user owns because both are prepped.

Recommendation:
- Decide the landing order with the user, and give c0053 a `depends_on` or an explicit "lands before R0019" note.
- If c0053 lands first: tell R0019's prep now, so that its gate spec exempts `scripts/tracker/publish.luau` (the private index) and its fence keeps fixture hooks working. For example, the injected `pre-push` could chain to `$(git rev-parse --git-path hooks)/pre-push` when it exists. Add a case to c0058 that a fixture's own `pre-push` still runs.
- If c0058 lands first: re-prep c0053's specs against the fence. Use no `GIT_CEILING_DIRECTORIES` and no fixture hook. Induce the race with a wrapper `git` on `PATH` in the fixture, or with a `publish.commit` test seam.
- Either way, rewrite R0020's Order & dependencies to state the code overlap. Re-run E7 under the other raft's fence before `design: ready`.

### F3 [high] Any terminal can give back another terminal's claim: published backward moves have no ownership check
Where: `cmd.status` in `prototype.patch` (the published path checks only `canMove`/`canClaim` against origin); the tracker skill's Sync and claim section ("give the claim back with `status <R-id> prepared`"); RC1 ("two terminals cannot both claim or start the same item").
Evidence:
- `status R0001 prepared` from `active` is an allowed move from any worktree. The code removes the claim file only if one exists; it never requires one. Terminal B, refused by `start R0001` (`R0001 is active on origin/main`), can run `status R0001 prepared` and then `start R0001`. Both terminals now hold branches and draft PRs for one raft.
- In the same way, `status <issue> new` (`preparing>new`) from any terminal releases an issue claimed by another terminal's `new raft`. `raft:` is never published, so nothing on origin says who holds it, and the next `new raft` takes it.
- The commands spec runs every give-back from the owning worktree (`ws`, `wt`), so no case can see this. The refusal text points an agent toward a status move, and the skill documents give-back as the recovery for a failed start, so an agent that is "fixing" a refusal will find this path.
- The stamp, which the user asked for so that ownership is visible, is never used to authorize anything except `start`'s resume.

Critique: the tempting fix is to require the claim file for `active>prepared`. That covers `start` but not prep claims, which have no claim file, and it strands a claim whose worktree was deleted.

Consequences: ownership needs a record for every claim, plus an explicit override for the abandoned-terminal case, which is a user-facing rule.

Recommendation:
- Write `.cache/tracker-claim-<id>` for every claim: `new raft` (the raft), `status <R-id> preparing`, `status <id> preparing` and `start`.
- A published move out of a claimed state (`preparing>new`, `prepared>preparing`, `active>prepared`) requires that origin's stamp equals this worktree's saved stamp, or `--force`. The tracker skill says `--force` is only for a terminal that is known to be dead, and the refusal names it.
- Commands cases:
  - a second worktree's `status R0001 prepared` on an active raft is refused and leaves origin unchanged;
  - `--force` succeeds;
  - a second worktree's `status <member> new` on a claimed issue is refused.
- Rules rows (mutant: no ownership check).

### F4 [medium] The cutover step leaves in-flight preps unstartable, cannot reserve their raft ids, and misstates today's collisions: R0019 is now double-allocated too (repeat of review-003 F4)
Where: R0020 Order & dependencies; the tracker skill's Sync and claim section, "Cutover" bullet; `git worktree list`.
Evidence:
- **Unstartable**: the cutover tells each open prep to claim its members with `status <id> preparing`. That stamps them `preparing-…` on origin. The prep's raft exists only on its branch, so the carried `status <R-id> prepared` is refused (`R0001 is not on origin/main`; reproduced). After the prep PR merges, the members stay `preparing`, and `start` refuses (reproduced: `c0001 is preparing on origin/main, not prepared`). A prep that skips the cutover step has no stored stamps, derives `prepared` from `design: ready`, and starts fine. So the documented step is the harmful one.
- **Not reserved**: "check its raft id against `tracker.sh status`" sees only origin. A local-only raft id stays unreserved until its prep PR merges, so any later `new raft` elsewhere can take it. No command publishes an existing local raft.
- **Facts**:
  - R0020 describes "R0019 (c0052 renumber advances by one, c0058 ...)" as one raft. In fact two worktrees each hold their own R0019: `prep-renumber-step-one` has `issues: [c0052]`, and `prep-check-isolation` has `issues: [c0058]`.
  - R0018 is still double (`prep-beta-poll-transient-errors` `[c0051]`, `prep-tracker-hardening` `[c0055 … c0630]`).
  - Five prep worktrees are open, not the ones the document names.

Recommendation:
- Change the cutover to: "do not stamp members of a raft that is not on origin. Land the prep first (members then derive from `design`). If a member must be held before it lands, run `status <id> preparing` and, before the prep commit, `status <id> prepared` for each member (a lone carried move)." Alternatively, add `status <R-id> preparing --publish-raft` to publish an existing local raft document. That is a new creation path through the publisher, and it needs its own cases.
- Correct the R0019 description in R0020, list all five open preps, and report both double allocations (R0018 and R0019) to the user. Resolve the R0019 one together with F2, because those two rafts are the two colliding preps.

### F5 [medium] Plausible mutants of the round-3 fixes survive: an `os.time()` seed, and a guard on only the four commands the spec tries
Where: Rules and mutants rows "Stamps come from real entropy ..." (`run`, listing only "constant seed" and "the saturating `os.clock` seed") and "A tracker command that publishes or syncs refuses ..." (`run`); `commands :: stamps from separate processes differ ...`; `commands :: a tracker command in a directory that lost its .git refuses ...`.
Evidence:
- **Seed**: with `entropy()` replaced by `return os.time()` (the "tempting fix" review-003 F1 warned about), `status.spec` and `commands.spec` give 34 passed, 0 failed. The two stubs being compared are made several seconds apart, so any time-based seed passes. Two terminals that make the same move in the same second, which is exactly the case the stamp is for, then write the same line.
- **Guard**: the lost-`.git` case tries only `new issue`, `status`, `sync` and `worktree zz`, plus `new issue` under `PICKMAN_PUBLISH=0`. A guard that is an allow-list of those commands passes it, and so does one that skips `start`, `done`, `commit`, `renumber`, `migrate`, `worktree-prune`, `focus` or `check`. The Rules row's own wording ("publishes or syncs") describes that weaker guard, not the design's "every command except the read-only ones".

Recommendation:
- Make the stamp case run two `new issue` processes **concurrently**, started together (for example one `bash -c 'a & b & wait'`), and compare their stamps. Add the `os.time()` mutant to the row.
- Drive the lost-`.git` case over every command in the usage table that is not on `READ_ONLY` (`start R0001`, `done R0001`, `commit`, `renumber`, `migrate`, `worktree-prune`, `check c0001` and so on). Assert that each one is refused with "repository root". Add a case that the read-only list is exactly the eight names. Fix the row's wording.

### F6 [low] `prompt` is exempt from the guard although it can create, and under publishing claim, a raft
Where: `READ_ONLY` in `prototype.patch` (it includes `prompt`); `cmd.prompt` (calls `cmd.new({"raft", …})` for an issue without a raft); the tracker skill, which itself calls it "a raft-creating `prompt`".
Evidence:
- In a `.git`-less directory under an ignored `.cache/` inside an outer worktree with an origin, `worktree zz` was refused by the guard. `prompt c0001 --stdout` was not refused. It reached the publishing `new raft` path against the **outer** repository.
- It stopped only because `publish.commit` runs `git ls-tree … tracker/` with a cwd-relative pathspec, which lists nothing from a subdirectory (`new raft: c0001 is not on origin/main`). With `PICKMAN_PUBLISH=0` it wrote `tracker/rafts/R0001` into the directory without any guard.
- Separately, with publishing on, `prompt <issue>` for a `design: ready` issue now always refuses, because the issue is `prepared`, not `new`.

Recommendation:
- Take `prompt` off `READ_ONLY`, or guard only its raft-creating branch.
- Run `ls-tree` with `--full-tree` (or from `rev-parse --show-toplevel`), so the publisher does not depend on an accident of the cwd.
- Either drop `prompt`'s raft creation (make-prompt already sends a raft-less issue back to ticket-prep) or document its refusal.

### F7 [low] Skill text left inconsistent by `skills.patch`
Where: the tracker skill: the Worktrees intro ("Every change ... lands by pull request") and the heading "Lifecycle: the directory is the status"; execute-raft Phase 0 step 1; `.github/workflows/board.yml`.
Evidence:
- c0053's Solution says to update the tracker skill's Worktrees rule 1 for the exception. The patch adds the exception only in the new section, so the Worktrees text still states the absolute rule, and the Lifecycle heading contradicts the new `status:` field.
- execute-raft's "Run `scripts/tracker.sh sync` in the worktree you launched in, or work in the raft's worktree: …" makes the sync optional on the second path. A reused raft worktree, created by `launch` earlier, then starts from a stale base.
- `board.yml` rebuilds on every push to `main`, so each tiny state push now runs it. The "Wasted CI" risk covers only `check.yml`.

Recommendation:
- Add "(except tracker state, see Sync and claim)" to the Worktrees intro.
- Rename the heading to "Lifecycle: the directory and the status".
- Make execute-raft step 1 "`cd` to the raft's worktree, then run `scripts/tracker.sh sync`".
- Either give `board.yml` the same `paths-ignore`, or accept the extra runs in Risks.

Verdict: changes

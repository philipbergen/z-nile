# Review 002: R0200 (design mode)
Inputs: worktree prep-publish-state-to-main at fc55fc2 plus uncommitted prep files: `tracker/rafts/R0200/{R0200.md,check.sh,design-review-001.md,design-refute-001.md}`; `tracker/issues/c0510/{c0510.md,check.sh}`, `acceptance/{status,publish,commands}.spec.luau`, `replacements/c0041-worktree.spec.luau`, `experiments/{status.luau.txt,publish.luau.txt,prototype.patch}`; `scripts/tracker/main.luau`, `store.luau`, `scripts/tracker.sh`; `tests/acceptance/c0041/worktree.spec.luau`; `.github/workflows/check.yml`; review, tracker, testing, ticket-prep and execute-raft skills; `origin/main` at a3ac240. Runs were made in scratch clones outside the repo (removed afterwards):
- Prototype applied with the c0041 replacement: `lune run tests/run` gave 560 passed, 0 failed, 91 spec files. `scripts/check.sh --full` gave GATE PASSED. The three c0510 specs gave 38 passed. This reproduces E7.
- `tracker.sh check c0510` on an unpatched copy: AC1-AC3 fail on the missing modules, AC4 passes, and AC5-AC8 fail with their own messages. These are the right reasons.
- The sequestered specs of c0450-c0480 give the same pass and fail set (9 passed, 51 failed, failing because those issues are not implemented) with and without the prototype.

Dropped from review-001: F1 (fixed by the c0041 replacement, AC8 and the whole-directory AC4; see F1 below for the stale base), F2 (the sha is pinned per try and the push carries a lease, both verified in `publish.luau.txt`), F3, F6 (user decision), F7, F8, F9, F11 and F12.

### F1 [high] The raft id R0200 is already used on `origin/main`, and the prep is four commits behind it
Where: `tracker/rafts/R0200/` (whole directory), c0510 frontmatter `raft: R0200`, R0200 `check.sh` (`members R0200`, `promote-check R0200`), and E7's counts.
Evidence: `git log origin/main` shows `c9e62d4 tracker: prep R0200 slow game speed (f0520) (#28)` and `a3ac240 R0200: Slow the game by 50% (#29)`. `git ls-tree origin/main tracker/rafts` lists `tracker/rafts/done/R0200/{R0200.md,check.sh,...}`. This worktree's merge base is fc55fc2.

The prep PR would add a second R0200, this one in backlog. `store.get("R0200")`, `members R0200` and `tracker.sh check R0200` would then see two items with one id, and the raft check.sh would run against whichever one the store finds first. This is exactly the collision c0510 exists to prevent, and it is happening to c0510's own prep. Other terminals' prep worktrees also hold R0180 (prep-beta-poll-transient-errors) and R0190 (prep-renumber-step-one, which contains c0500), and those are not on `origin/main` either.

The stale base also invalidates E7. `origin/main` has three more promoted spec files (`tests/acceptance/f0520/*`) and a changed `tracker/rafts/R0090/check.sh`. The recorded "91 spec files, 560 cases" and "AC4 passes" were measured on fc55fc2.

Critique: the tempting fix is to rename the directory by hand. Every reference to R0200 must change too: the c0510 frontmatter, the raft check.sh, the prose ("R0200 RC0", the title of `design-review-001.md`), and the c0510 doc's test plan.

Consequences: until c0510 lands, the next free id has to be agreed across terminals by hand, because R0180 and R0190 are taken locally but not published. Renumbering also changes the branch name (`R<id>-publish-state-to-main`).

Recommendation:
- Merge `origin/main` into the prep worktree.
- Renumber the raft to a free id above every raft on origin and in the other prep worktrees (R0200 or higher today), including every textual reference. Rename the review and refute files' headings too.
- Re-run E7 (the full suite and `check.sh --full` with the prototype) on the merged base and record the new counts.

### F2 [high] A test fixture that loses its `.git` silently becomes the real repository, and with this raft a tracker command in it pushes to GitHub `main`
Where: c0510 Commands ("Publishing is on when the repo has an `origin` and `PICKMAN_PUBLISH` is not `0`"), the `publishing()` helper in `prototype.patch`, and `scripts/tracker.sh` (`cd "$(dirname "$0")/.."`, then git discovers the repository by walking up from that directory).
Evidence: this happened to the real repository during this review, from another session (not from this review's scratch copies).
- At 23:56:34, `/Users/philipbergen/code/pickman/.git/config` lost its `origin` remote. `git remote -v` is now empty and `refs/remotes/origin/*` is gone.
- At the same moment, `git worktree list` gained a stray registration: `/Users/philipbergen/code/pickman/.worktree/R0140/.cache/wt-e2e/main/.worktree/R0010`, detached at a3ac240.

`.cache/wt-e2e` is the fixture of `tests/acceptance/c0041/worktree.spec.luau` (`clone.isolated(root, seed)`, then `git(seed, { "remote", "remove", "origin" })`, then `tr(main, { "worktree", "R0010" })`). It ran in the R0140 worktree, whose raft makes specs run concurrently. When the fixture repo's `.git` was missing (a concurrent re-creation removed it), git walked up from `.cache/wt-e2e/seed` to the enclosing real worktree. It then ran the fixture's `remote remove origin` and `worktree add` against the real repository.

Today that damage stays local. After c0510, the same fall-through in any spec that calls `tracker.sh new` or `start` sees the real `origin` (`https://github.com/philipbergen/pickman`). `publishing()` returns true, and `publish.commit` pushes a stub or claim straight to GitHub `main`. Nothing appears in the real working tree, because the push is plumbing. The whitelist cannot catch it: a fixture's `new issue c alpha` is a legitimate item path with an id allocated from the real repository's union. Specs exposed to this include c0510's own commands spec (publishing on, run five times by AC3, RC1 and RC2) and every existing spec that runs `tracker.sh new` or `start` in a fixture.

Critique: the tempting fix is `PICKMAN_PUBLISH=0` in more fixtures. That does not protect the commands spec, which needs publishing on, and it relies on every future spec remembering the flag.

Consequences: the guard has to live in the tracker, because the tracker is what pushes. A guard that fails closed must not break the real launch flow, in which `tracker.sh` lives in the worktree it runs in.

Recommendation:
- Every tracker command, and at least `publishing()` and `publish.commit`, refuses when `git rev-parse --show-toplevel` differs from the directory `tracker.sh` changed into (the root that holds the running `scripts/`). It fails with a message, not by quietly going local.
- Optionally, `tests/run` also exports `GIT_CEILING_DIRECTORIES=<root>/.cache` for spec processes.
- Spec case: an outer fixture repo with a bare origin, and inside it a directory holding a copy of `scripts/` but no `.git`. `tracker.sh new issue c x` run there fails with the toplevel message, and the outer origin's `main` is unchanged.
- Add a Rules and mutants row for it.
- Separately, report the damaged real repo to the user (the missing `origin` remote and upstream config, and the stray worktree entry); this review did not touch it.

### F3 [high] The derived status ignores `raft:`, so 15 issues already in draft rafts, and those rafts, read as `new`, and `new raft` now steals them
Where: c0510 "The model", Effective status ("any other backlog item gives `new`"); Commands, `new raft` ("Each member must be on `origin/main` with effective status `new`"). The publishing branch of `cmd.new` in `prototype.patch` returns before the old `already belongs to {current}` check.
Evidence: on `origin/main`, f0180-f0320 (15 issues) carry `raft: R0100|R0110|R0120|R0150` with `design: draft` and no `status:`, and R0100, R0110, R0120 and R0150 are `design: draft`. The same applies to anything prepped before this raft merges (c0500 in R0190, the R0180 prep). Scratch run on the prototype (seed = the repo tree, a bare origin, a worktree):
```
$ tracker.sh status f0190      -> new
$ tracker.sh status R0100      -> new
$ tracker.sh new raft feature steal f0190 --single
tracker/rafts/R0180/R0180.md
f0190.md: raft: R0180 / status: preparing-raging-silver-marble
origin R0100.md: issues: [f0190, f0200, f0210, f0220, f0310, f0320]
```
The old code refuses with `f0190 already belongs to R0100`. The prototype claims f0190 for a new raft while R0100 still lists it. `status` also tells every terminal that these items are free.

The documents also never say how to claim a raft that already exists, which is the next prep of R0100-R0150. ticket-prep only says "claims with `new raft`".

Critique: the tempting fix is to restore the `raft:` check inside `build` only. Then `status` still lists those items as `new`, and nothing claims an existing raft.

Consequences: the derived rule gains an input (`raft:` on issues, and the existence of the raft document for rafts). It has to agree with the published claim, which deliberately does not write `raft:` on origin.

Recommendation:
- Derive `preparing` for a backlog issue with a non-empty `raft:` and `design` not `ready`, and for any backlog raft with `design` not `ready`. The `status.derive` signature gains the raft field.
- Keep the old refusal in the publishing `new raft` (a member whose origin `raft:` is non-empty and differs is refused, naming that raft).
- Document in the tracker and ticket-prep skills that an existing raft is claimed with `tracker.sh status <R-id> preparing`, which moves its members too.
- Spec cases:
  - `status :: derives preparing for an issue that names a raft`;
  - `commands :: new raft refuses an issue that already belongs to a raft`;
  - `commands :: status <existing draft raft> preparing claims it and its members`.
- Add mutant rows.

### F4 [medium] `withFront` matches the key in the middle of a line, so a title containing `status:` absorbs the claim, which is then silently lost; the frontmatter-only rule lets it through (partly a repeat of review-001 F10)
Where: `prototype.patch` `withFront` (and `store.setFront`, which it replaces): pattern `` `(\n?){key}:[^\n]*\n` `` with an optional newline. `publish.luau.txt` `body()`.
Evidence: run in Lune with the prototype's function:
```
withFront("---\nid: c0600\ntitle: Show claim status: on the board\ncreated: x\nstatus: new-a-b-c\n---\nbody\n", "status", "preparing-d-e-f")
-> title: Show claim status: preparing-d-e-f
   status: new-a-b-c
```
`new raft`, `start` and `status` would publish this edit. The body is unchanged, so `commit` accepts it. The item stays `new` on origin, so a second terminal can claim it again. The same applies to the `raft` key and a title containing `Draft:`, through the local `setFront(doc, "raft", …)`. No title on `main` contains a colon today, so this is latent, but titles are free text that make-issue edits.

`body()` has two further holes:
- It returns the whole text when there is no opening fence. A change whose content is exactly origin's body, with the frontmatter deleted, therefore passes (`body("---\nid: x\n---\nB\n") == body("B\n")` is `true`).
- The frontmatter itself is unbounded, so any number of lines can be added above the closing fence.

Critique: the tempting fix is to anchor the pattern only. That fixes this bug, but the publisher's rule still allows any frontmatter edit, while every published edit is in fact a `status:` line.

Consequences: a narrower rule needs `new` (creation) kept separate from changes, which `commit` already does.

Recommendation:
- Anchor the key at a line start (`"\n" .. key .. ":"` on `"\n" .. block`) in `withFront`.
- In `commit`, an existing document may differ from origin's only in its `status:` line: compare both texts with the `^status:[^\n]*$` line removed, after confirming that each has exactly one frontmatter block. Reject CRLF (`\r`) in published content.
- Spec cases: a title containing `status:` keeps its text and the real status moves; a change that deletes the frontmatter is refused; a change that adds any other frontmatter line is refused.
- Add mutant rows.

### F5 [medium] A raft move reads members from origin's `issues:` list, so members added during prep are stranded at `new` and dropped members are marked `prepared`
Where: c0510 Commands `status` ("a move of a raft moves its members (read from the raft's `issues:` list)"); `cmd.status` build reads `frontOf(text).issues` from the **origin** raft document; `start` checks the **local** `store.members` against origin.
Evidence: the raft document is published once by `new raft`. Membership edits made during prep live only on the prep branch until the prep PR merges.
- Suppose prep adds c0600 (published `new-…`) to the raft. The carried `status R prepared` moves only origin's list, so c0600 keeps `status: new-…` on `main` after the prep PR merges, and an explicit field beats `design: ready`. `start` then refuses forever (`c0600 is new on origin/main, not prepared`). The only way out is `status c0600 preparing` (published) followed by a carried `prepared`, which needs another PR.
- A dropped member is moved to `prepared` locally and reaches `main` as `prepared` with no raft.

No spec changes membership. The Rules row "A raft move moves its members" covers only an unchanged list.

Recommendation:
- Read the member list for a carried move from the local raft document (the one the prep PR will land), and for a published move from origin.
- `status <R-id> prepared` (carried) refuses while a local member is not `preparing` on origin, naming it and the command that claims it (`status <id> preparing`).
- Document in ticket-prep that adding an issue to a raft during prep starts with that claim, and that dropping one is followed by `status <id> new`.
- Spec cases: a member added locally, but unclaimed, makes the carried move refuse; after `status <id> preparing` it is carried; a dropped member is not touched.

### F6 [medium] execute-raft's own sequestration check is not changed, and every `sync` brings in other items' published `check.sh` files, so it fails falsely; the review skill's member-scoped diff instead hides edits to other items' sequestered files (partly a repeat of review-001 F5)
Where: execute-raft SKILL.md Phase 3 step 3 (`git diff <start-commit> -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` must be empty); c0510 Implementation step 7 and Skills (only "review: scope the sequestration diff to `tracker.sh members` paths and the raft directory"); AC6 (checks neither).
Evidence: every `new issue` publishes a new `tracker/issues/<id>/check.sh`. execute-raft now starts with `tracker.sh sync`, which merges `origin/main`. After the first sync following `start`, any stub another terminal created makes the execute-raft diff non-empty, so the executor's Phase 3 check fails and points at files the executor never touched. Nothing in the documents tells the executor to change that skill text.

The review-side fix narrows the pathspec to the raft's own members. An executor that edits **another** item's sequestered `check.sh` or acceptance spec is then invisible to the code review, although the old rule flagged it as high. One realistic case: R0160's c0480 spec also exercises `start`.

Critique: scoping by membership trades a false positive for a false negative.

Consequences: the diff has to separate "changed by this branch" from "merged in from `main`", which git's three-dot form does.

Recommendation:
- Both skills (execute-raft Phase 3 step 3, and review Code mode item 2) use `git fetch origin main && git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'`. It must list nothing except `R100` renames (the `start` move to `active/`).
- Add a line to Implementation step 7 for execute-raft.
- AC6 greps both skills for `origin/main...HEAD` in the sequestration line.
- Spec case or AC check: none needed beyond AC6, but record the rule in the Rules table as a `reasoned` row.

### F7 [medium] Resuming a claim is only half tested: an implementation that never writes the claim file passes every spec
Where: Rules and mutants row "A claim by this terminal can be resumed, another terminal's cannot", marked `run`; `commands :: a claim made by this terminal can be resumed ...`; `cmd.start` (`if r.sha then fs.writeFile(claimFile(raft.id), claim) end`).
Evidence: I removed that `fs.writeFile` line from the prototype, and `lune run tests/run -- tracker/issues/c0510/acceptance/commands.spec.luau` gave `18 passed, 0 failed`. The case publishes the claim with `status R0010 active`, writes `.cache/tracker-claim-R0010` by hand, and detaches HEAD. So `start`'s own write, the real launched-worktree path (already on `R0010-<slug>`, `onBranch = true`), and the actual failure the feature exists for (a `start` that stops after its claim) are never exercised.

The file is also written only after `publish.commit` returns. A process that dies between the push and the write is not resumable, which contradicts "a start that died right after its push can be finished". After the local `tracker: start` commit, a re-run refuses with `already active`. That is consistent with "finish by hand", but neither case is stated precisely.

Recommendation:
- Write the claim file **before** the push, with the stamp chosen outside `build`, and remove it when the publish is refused.
- Spec case: in a worktree created by `tracker.sh worktree R…`, make `mergeOrigin` fail after the claim (for example, a conflicting local commit on the raft doc). Then resolve it and re-run `start`: it completes, publishes nothing new, and `.cache/tracker-claim-R…` exists. A second worktree is still refused.
- Mark the "never written" mutant `run`.

### F8 [low] AC6 and AC2 can be satisfied by text that is wrong
Where: c0510 `check.sh` `skills_carry_sync_and_claim`; AC2's wording.
Evidence:
- `grep -q 'tracker\.sh sync'` also matches `tracker.sh sync --fetch`, so execute-raft or ticket-prep could carry the fetch-only form and pass.
- The review skill passes while it also keeps a bare `tracker.sh sync` step, which is the hazard review-001 F5 found.
- AC2 says the publisher "retries … locked fetches", but its Rules row is `reasoned` because no spec can provoke that failure.

Recommendation:
- Grep the five working skills for `tracker\.sh sync([^ -]|$)`.
- Fail if review or metrics contain `tracker\.sh sync([^ -]|$)`.
- Drop "locked fetches" from AC2's text, or mark that part as not checked.

### F9 [low] Smaller behaviour gaps in the commands
Where: `cmd.new` (publishing branches); c0510 Commands.
Evidence:
- `new issue … --raft R0100` for a **backlog** raft silently drops `--raft`: the publishing path writes `RAFT = ""`, while the old path wrote it. The usage text still advertises the flag.
- `new raft` does not require a clean tree before it claims. If `mergeOrigin` then refuses (local edits to a member), the claim is on origin but `raft:` is never written locally. A re-run is refused because the members are `preparing`, and the recovery (`git merge origin/main`, then `setFront` by hand) is not documented.
- The local `tracker: <R> members` commit edits `raft:` (line 5), directly above `depends_on:`. I confirmed in git that a capture PR editing `depends_on` conflicts with that commit. The refute is right that the **capture** side now merges cleanly, but the prep branch then conflicts on its next sync. This is within the user's accepted "loud signal", but it should be stated in R0200 Risks.

Recommendation:
- Refuse `--raft` with a backlog raft in publishing mode (`--raft is only for emergent issues of an active raft`).
- Check that the tree is clean before `new raft` publishes.
- Add one sentence each to the tracker skill and R0200 Risks.

Verdict: changes

# Review 001: R0200 (design mode)
Inputs: worktree prep-publish-state-to-main at fc55fc2 plus uncommitted prep files: `tracker/rafts/R0200/R0200.md`, `check.sh`; `tracker/issues/c0510/c0510.md`, `check.sh`, `acceptance/{status,publish,commands}.spec.luau`, `experiments/{status.luau.txt,publish.luau.txt,prototype.patch}`; `scripts/tracker/main.luau`, `store.luau`; `.github/workflows/check.yml`; tracker, testing, review, execute-raft, make-issue skills. Spot runs were made in a scratch clone with the prototype applied, never in the worktree. Results: the three acceptance specs pass (28 cases, not 29); the existing promoted specs fail (F1); a race reproduces (F2); a surviving mutant (F3); a git merge conflict (F6).

### F1 [high] The prototype breaks 13 cases of existing promoted acceptance specs, which the executor may not edit, so RC0 cannot pass as designed
Where: c0510 "Regression guard", AC4, "Unknowns & experiments" ("the existing lifecycle, worktree-fetch, board and migrate specs still pass"); R0200 RC0.
Evidence: in a scratch clone with `status.luau`, `publish.luau` and `prototype.patch` applied, `lune run tests/run -- tests/acceptance/c0041/worktree.spec.luau tests/acceptance/c0430/workstreams.spec.luau tests/acceptance/c0440/launch.spec.luau tests/acceptance/c0070/done-order.spec.luau tests/acceptance/c0420/naming.spec.luau` gave `65 passed, 13 failed`. The same command on an unpatched clone gave `65 passed, 0 failed`. Failures:
- c0041 `start inside the worktree reuses the branch and pushes`: `start failed (1): R0010 is new on origin/main, not prepared`. The fixture sets `design: ready`, but the template's new `status: new` line wins over it (see F7).
- c0041 `start and new are refused in the main checkout` (`:199`) and `new issue works in a named worktree` (`:306`, which expects a dirty tree, but publishing leaves it clean).
- c0041 `GitHub origin opens the draft PR`: `fetch failed: remote: Repository not found`. The fixture's fake GitHub fetch URL now gets fetched.
- c0041 also fails `non-GitHub origin skips the draft PR`, four `worktree-prune` cases and `worktree refuses a done raft` (they cascade from the start failure).
- c0430 `tracker.sh commit refuses while a squash merge is unresolved` (`R0010 is new on origin/main, not prepared`) and `stream review files are not review rounds`.

Even with the status fixed, c0041 `:240` asserts `HEAD~1 == origin/main` after `start`, and `start` now adds a publish commit and a merge, so that case fails by design. AC4 lists only lifecycle, worktree-fetch, board, migrate-odd and spend, so it misses all of this. RC0 (`check.sh --full`) catches it at the end, but the testing skill says promoted specs are "never edit", and the execute-raft stop conditions forbid changing them. The executor would hit a guaranteed stop.

Critique: the tempting fix is to let the executor "adjust" c0041 and c0430, which breaks sequestration. The other tempting fix is to turn publishing off whenever the origin is not GitHub. That still breaks c0041's GitHub-origin case and makes the commands spec need an override.

Consequences: changing promoted specs is a test fix, which is chore scope. It needs an explicit decision recorded at prep time, plus the exact new expectations, or the code reviewer flags it as a sequestration high.

Recommendation: decide in prep, not during execution.
- **Option (a)** (preferred): publishing is opt-in in fixtures. It is on only when `PICKMAN_PUBLISH=1`, or when `PICKMAN_PUBLISH` is unset and `remote.origin.pickmanPublish` is true. The real repo sets that config in `scripts/setup.sh` and `tracker.sh worktree`. Every pre-existing fixture then stays local and unchanged. The commands and publish specs set the variable explicitly. Add a spec case: a fixture with a plain local origin and no opt-in publishes nothing.
- **Option (b)**: list `tests/acceptance/c0041/worktree.spec.luau` and `tests/acceptance/c0430/workstreams.spec.luau` in Touched modules, and write their new versions in prep as part of the sequestered set (diffed by the reviewer against the start commit like any acceptance file).

Either way:
- Re-run every `tests/acceptance/*` spec and `tests/tooling/*` spec against the prototype and record the result.
- Make AC4 run `tests/acceptance` and `tests/tooling` whole, not a hand-picked list.

### F2 [high] The compare-and-set is not one: `origin/main` is resolved by name several times per try, and sibling worktrees share that ref, so a publish can overwrite another terminal's stub or claim
Where: c0510 Design, Publisher, `commit`; prototype `publish.luau.txt` lines 24-43; Scalability ("`origin/main`'s push is the compare-and-set").
Evidence: the prototype runs `fetch`, then `ls-tree origin/main`, then `build`, then `read-tree origin/main`, then `commit-tree -p origin/main`, then push. All terminals are worktrees of one repository and share `refs/remotes/origin/main`. Any `git fetch`, or any successful push (which updates the tracking ref), from a sibling worktree moves that ref between `build` and `read-tree`. Scratch reproduction:
- Worktrees `w1` and `w2` of one clone. `w1`'s build saw no c0020 and chose c0020.
- Inside that window, `w2` published `tracker/issues/c0020/c0020.md = THEIRS`.
- `w1` then built on the new tip and pushed.

Output:

```
w2 published true eeb9024…
w1 build sees c0020 taken: false
w1 true f5fbac8…
c0020 on origin: MINE
```

`w1`'s push was a fast-forward, so the remote accepted it and `w2`'s stub was silently overwritten. The same happens to `new raft` claims and `start`. Concurrent fetches in one repository also contend for `refs/remotes/origin/main.lock`. The prototype returns `fetch failed` on the first such error, with no retry.

Critique: this is the property the whole raft rests on ("no central lock because the push is the compare-and-set"). No spec exercises the window: the publish race tests use a separate clone (`other`) and a pre-push hook. That only covers the race the remote detects, not the local ref moving.

Consequences: pinning a sha means `read` must take the pinned sha too. Fetch contention then becomes a retryable case, not a fatal one.

Recommendation:
- After the fetch, resolve `local base = rev-parse origin/main` once per try. Use `base` for `ls-tree`, `read`, `read-tree` and `commit-tree -p`.
- Push `<sha>:refs/heads/main`, which is a fast-forward only from `base`. Optionally add `--force-with-lease=refs/heads/main:<base>` for clarity, never `--force`.
- Treat a failed fetch (lock contention) as a consumed try, not a hard failure.
- Add a publish spec case in which the build callback moves the shared ref: a sibling worktree of the same clone publishes, or fetches after a push from `other`. Expect build to run twice, the second id to be chosen, and the sibling's file intact.
- Add a Rules and mutants row for "re-resolve `origin/main` by name".

### F3 [high] Published `status <id> <to>` moves are untested: an implementation that never publishes them passes every spec
Where: c0510 Test plan AC3; Rules and mutants row "A carried move edits locally only; a published move pushes" (its only mutant is the inverse).
Evidence: in the scratch prototype I replaced the move body with a local-only edit for every valid move (`return {}` from build, then `store.setFront` locally). `commands.spec.luau` result: `13 passed, 0 failed`. The only `status <id> <to>` calls in the spec are the carried `prepared` moves and refused moves. `new raft` and `start` cover publishing for their own transitions, not for the `status` command. So `preparing>new`, `prepared>preparing` and `active>prepared` (abandon and reopen, which are the recovery paths for F4) can be local no-ops and AC3 still passes.

Critique: AC3 says "publishes … status moves". A hard-coded wrong implementation passes it.

Consequences: a published move followed by `mergeOrigin` also needs to be checked for the clean merge into a worktree whose local file differs. One example is the carried `prepared` edit from earlier in the same spec.

Recommendation: add a commands case. Take an item that is `preparing` on origin and run `status <id> new`. Assert:
- origin's doc says `status: new`;
- origin gained exactly one commit touching only that file;
- the worktree HEAD contains origin's tip and is clean.

Add a second case for `active>prepared` on a started raft at its backlog path. Add a mutant row "published move edited locally only" with `run`.

### F4 [high] `start` publishes `active` before any of its fallible steps, so a failed start can never be retried, and run from the main checkout it claims and then refuses
Where: c0510 Commands, `start`; `prototype.patch` (the publish block precedes `refuseInMainCheckout("start")`, `switch -c`, `git mv`, commit, branch push and `gh pr create`).
Evidence: in `main.luau`, `refuseInMainCheckout("start")` runs only inside `if branch ~= current`, which comes after the inserted publish block. Running `tracker.sh start R0010` in the main checkout therefore:
1. publishes `active` for the raft and its members;
2. runs `git merge origin/main` in the main checkout;
3. fails with "must run inside a worktree".

The same applies to any later failure: `switch -c` on an existing branch, a rejected branch push, or `gh pr create` without auth. Re-running `start` then hits `canMove("active","active") == false` and refuses with "R0010 is active on origin/main, not prepared". The only way out is undocumented: `status <id> prepared` on the raft and on each member separately. That route is itself untested (F3).

Critique: c0041 `start and new are refused in the main checkout` fails for this reason (F1). The tempting fix is to move the publish after the push or PR creation. That widens the window in which two terminals both create branches and PRs.

Consequences: the order must still claim before visible side effects, but the claim has to be resumable by its owner. Ownership needs to be recognisable.

Recommendation:
- Run every local precondition first: clean tree, design ready, main-checkout refusal, and the branch not already existing elsewhere. Then publish the claim.
- Make `start` idempotent for its owner. Record the branch in the published commit (for example `status: active` plus the raft's branch name in the commit message), and let `start` continue when origin says `active` and the local branch `R0010-<slug>` exists or is about to be created by this terminal.
- Document the recovery: `tracker.sh status R0010 prepared` moves the raft and its members back in one commit. Make `status` on a raft carry its members.
- Spec cases: start in the main checkout publishes nothing; a start whose branch push fails can be re-run to completion; a second terminal is still refused.

### F5 [high] "Every skill starts with `tracker.sh sync`" makes reviewers and stream agents merge `origin/main` into the worktree they review, which breaks their output contract and the diffs they judge
Where: c0510 Skills, Implementation step 7, AC6 (requires `tracker.sh sync` in the review skill); the review skill's Stream and Code modes; execute-raft Phase 2B and Phase 4 step 1.
Evidence: `sync` in a worktree is `git merge --no-edit origin/main`, which creates a commit. The review skill tells the reviewer to "write only that file: don't commit". Effects by mode:
- **Code mode**: the author has already posted "Review NNN started at <sha>". A reviewer that syncs moves HEAD past that sha, or leaves a conflicted merge in the author's worktree.
- **Stream mode**: the scope is `git diff <raft branch>...ws-<issue>`. A merge of `main` into `ws-<issue>` puts every main change since the raft started into that diff, and the skill says "anything else is a finding".
- **Sequestration**: code mode requires `git diff <tracker: start commit> -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` to be empty. Any merge of `origin/main` after `start` brings in other items' published `check.sh` stubs and merged prep files, which is a false high.

The same merge also comes from `tracker.sh new issue` run in a raft worktree for a postponable issue (tracker skill, Emergent issues; execute-raft Phase 4 step 7 deferrals): `new` always runs `mergeOrigin()` after publishing.

Critique: AC6 enforces the very text that causes this.

Consequences: sync needs a read-only form, and the review skill's sequestration diff needs scoping to the raft's own members.

Recommendation:
- Add `tracker.sh sync --fetch` (fetch only, never merges). The review skill (all modes) and metrics use it. The review skill's sequestration diff is restricted to the paths of `tracker.sh members <R-id>` and the raft directory.
- `new issue` run from a raft worktree (an active raft exists on the branch) publishes but does not merge. The stub reaches the branch at the Phase 5 merge.
- AC6 then checks `sync --fetch` in the review skill.
- Spec cases: `sync --fetch` leaves HEAD unchanged; `new issue` in a worktree with an active raft leaves HEAD unchanged.

### F6 [high] A stub is claimable as `new` before its capture PR lands, so another terminal can prep a one-line stub, and the published `raft:` edit conflicts with the capture PR's frontmatter
Where: c0510 Commands, `new raft` ("each member must be on `origin/main` with effective status `new`"); R0200 Risks (only `status:` is placed to avoid conflicts); make-issue step 3 ("Fill in the frontmatter: `title`, and `depends_on`").
Evidence: `new issue` publishes the stub immediately, and the capture PR fills in the body later. Terminal B's `new raft … c0510` succeeds while terminal A's capture PR is still open, so B preps from the stub. The published claim also rewrites `raft:` (line 5, directly above `depends_on:`). Scratch git test: a stub frontmatter where `cap` set `depends_on: [c0400]` and main set `raft: R0010` and `status: preparing` gave `CONFLICT (content): Merge conflict in c.md`. The capture PR then turns `DIRTY`, and the Merging rules post `BLOCKED:`.

Critique: E2 tested only a non-overlapping remote change. The Risks section argues conflict avoidance for `status:` alone, but claims also write `raft:`.

Consequences: there are five user-chosen states and no "capturing" state, so the guard must use existing data or a recorded user decision.

Recommendation: decide one of these in prep and record it.
- (a) `new raft` refuses a member whose origin doc still has the template Solution or Non-goals comment, with the message "not captured yet: its capture PR has not landed".
- (b) Ask the user whether a sixth state is wanted.

Also move the published `raft:` write out of the claim: membership can be read from the raft's `issues:` list, and the prep PR then carries `raft:`. Otherwise keep `raft:` but place it after `created:` next to `status:`.

Spec cases: a claim on a stub-only issue is refused; a capture branch that edited `depends_on` merges cleanly after a claim.

### F7 [medium] The template's `status: new` overrides the derived status, so an item made ready the old way is unstartable
Where: c0510 "The model" (an explicit field wins); `prototype.patch` templates add `status: new`.
Evidence: every item now created locally (`PICKMAN_PUBLISH=0`, no origin, or a fixture) carries `status: new`. Setting `design: ready`, which is what ticket-prep and every existing fixture do, no longer makes it `prepared`. `start` then refuses: this is the root cause of most of F1's failures. The same applies to anything prepped offline and pushed later through a PR.

Critique: with two fields that can disagree, nothing decides which one wins except the rule "field wins".

Consequences: either the template drops the line, or the rules reconcile the two fields.

Recommendation:
- Do not put `status:` in the templates. Write it only through published or carried moves; `withFront` appends it after `created:`, the last key, anyway. A missing field derives (`ready` gives `prepared`).
- Alternatively, let `effective` return `prepared` when the field says `new` or `preparing` but `design: ready` and the item is in backlog. Pin either choice with a status spec case.
- Add a commands case: an item created with `PICKMAN_PUBLISH=0` and made `design: ready` can be started once it reaches origin.

### F8 [medium] The publisher ignores the exit status of every plumbing step: a failed `commit-tree` pushes an empty refspec, which tries to delete `main`; a failed `update-index` publishes an empty commit as success
Where: `publish.luau.txt` lines 33-43 (only `fetch` and `push` are checked); Implementation step 1 ("Create … from the prototype").
Evidence: without a user identity, `git commit-tree` exits 128 ("no email was given"), so `sha == ""`. The prototype then runs `git push -q origin ":refs/heads/main"`, which is a deletion request. In a scratch bare origin it was refused only because `receive.denyDeleteCurrent` protects HEAD's branch, and the error loops for five tries and reports "push rejected". If `hash-object` or `update-index` fails, the tree equals `origin/main`'s, and an empty commit is pushed with `ok = true`. `new` then reports a stub that does not exist. Two concurrent publishers in one worktree share the fixed `pickman-publish-index`. The prototype also does not type-check: `promote-check R0200` on the scratch copy reports three `TypeError`s at `publish.luau(10-12)`, though step 1 says the modules "should pass".

Recommendation:
- Check every git call.
- Validate `sha` against `^%x+$` and length 40 or 64 before pushing.
- Name the index file with the process id, and remove it on every exit path.
- Refuse when the built tree equals the base tree.
- Spec cases: a broken identity returns `ok=false` with git's message and origin unchanged; a build that produces no effective change is a no-op, not a commit.

### F9 [medium] Raft ids are allocated from `origin/main` only, not from the union
Where: c0510 Commands (the union is stated for `new issue` only); `prototype.patch`: `statusLib.nextNumber(idsOf(paths, "raft"))`.
Evidence: a raft that exists only locally gets its number reused, and two branches then add/add on `<ID>/<ID>.md`. This happens to in-flight prep branches created before this raft merges, and to `PICKMAN_PUBLISH=0` rafts. That is exactly the collision c0510 exists to remove. No spec distinguishes the two allocations: the fixture's first raft is R0010 either way. No mutant row covers it.

Recommendation: use the union of local and origin raft ids, the same rule as issues. Spec case: a local unpublished R0020 makes `new raft` choose R0030. Add a mutant row.

### F10 [medium] The whitelist admits `check.sh`, which is executable and run by `tracker.sh check` and `done`, so unreviewed code can reach `main` by the direct push
Where: c0510 Publisher, `allowed`; R0200 Risks ("code … never use it").
Evidence: `publish.allowed("tracker/rafts/done/R0140/check.sh") == true`, and the same for every existing item's `check.sh`, including done and sequestered ones. The only legitimate need is creating a stub's template `check.sh`.

Recommendation: allow `check.sh` only when it is absent on the pinned base (creation), and enforce that in `commit`, not only in callers. Item `.md` writes after creation should be limited to frontmatter-only changes, by comparing the body below the closing `---` with the base. Spec cases: overwriting an existing `check.sh` is refused; a publish that changes a document's body is refused.

### F11 [low] `active>done` is called carried, but nothing performs it
Where: c0510 "Published or carried"; Commands, `done` ("unchanged").
Evidence: `done` moves items to `done/` with `status: active` still in the file. The skills are not told to run `status <id> done`, so the field is stale forever, and the effective rule hides it.

Recommendation: either make `done` write `status: done` in the same commit (one `withFront`), with a lifecycle assertion, or document that `done` is purely directory-derived and drop it from `carriedByPr`.

### F12 [low] Documentation and minor gaps
Where: c0510 Unknowns & experiments; `publish.allowed`; `sync`; `mergeOrigin`.
Evidence:
- The doc claims 29 cases; the three specs have 28.
- `allowed("tracker/issues/active/done/c0010/c0010.md")` is true, because the prefixes are stripped sequentially.
- The `sync` spec cannot tell `merge` from `pull --ff-only` in the main checkout: both fast-forward there.
- After a published `new raft` whose merge conflicts, the message "`tracker.sh sync` finishes the job" is wrong, because a conflicted merge blocks `sync`.

Recommendation:
- Correct the count.
- Strip at most one of `active/` or `done/`.
- Add a `sync` case where the main checkout has a local commit, so `--ff-only` must refuse.
- On a failed merge, run `git merge --abort` and print what to do.

Verdict: changes

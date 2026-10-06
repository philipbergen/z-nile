# Review 003: R0027 (design mode)
Inputs: prep worktree at 7c6fa30 plus its uncommitted prep edits (R0027.md, check.sh; c0081 and c0082 documents, check.sh, acceptance/*.spec.luau, experiments/prototype.diff); design-review-001/002 and design-refute-001/002; prototype worktree proto-r0270 at 03a7e7c (all ten new spec files byte-identical to the prep ones); origin/main 515bd7e (`tracker.sh sync --fetch`: unchanged); the review, testing, ticket-prep and tracker skills. Experiment I ran, in a clone of proto-r0270 under the session scratchpad (since removed): a mutant that drops the retired-number skip at every allocation call site in `main.luau` (F1).

The round-2 answers hold on reading and in the prototype:
- F1: `retired-id` is in c0082's table and audit.spec, and remap.spec's `late-y` branch shows a plain merge failing the audit with `remap` in the message. The consequence the author found (a legitimate post-compaction item colliding with a retired id) is real, and the retired-number skip answers it.
- F2: `publishFresh` wraps every `publish.commit` in `main.luau` except remap's (grep: only line 1211 calls `publish.commit` directly). remap.spec's stale case checks `status c0001 preparing` with "remap" in stderr, which kills the "only at allocation sites" mutant.
- F3, F4, F5: in the skill text, R0027 Risks, the testing skill and step 8, and skill-doc.spec asserts them.
No round-2 finding is repeated.

### F1 [high] The retired-number skip at the allocation sites has no spec: a mutant that drops it at every call site passes all of c0081's and c0082's checks
Where: c0081 Solution ("Retired numbers are never handed out again"); Rules and mutants row "retired numbers are skipped" (spec: `ids :: after a compaction, allocation skips every retired number`; mutant: `nextFree` ignores `retired`); allocate.spec and remap.spec (neither fixture has a map in which a retired number lies in the allocation's path).
Evidence: I changed the prototype's `main.luau` in three places: `reserve` passes `nil` instead of `retiredOf(read(idsLib.MAP_FILE))`; `localNumber` passes `nil` instead of `localRetired()`; `cmd.remap` sets `local retired = nil`. Results: allocate.spec 12/12 passed, remap.spec 9/9, compact.spec 17/17. ids.spec stays green too, because `ids.nextFree` itself is untouched. In remap.spec the counter after compaction is 3 and the retired numbers are 10 and 20, so the branch's two items (3, 4) never reach one. allocate.spec has no map at all.
What the mutant does in production: once the real counter reaches 90 after the compaction, `new` creates `c0010` (a retired id: old `c0010` maps elsewhere). From then on `real-tree.spec`, and so every PR's gate, fails with `retired-id … undo the merge of origin/main and run tracker.sh remap`. That message is wrong for this cause, and no merge is involved. The skip exists to prevent exactly this (refute 002 F1, consequences), and the Rules row covers only the pure function, not the three callers that must pass the map: origin's map when publishing, the local map offline, and origin's map in remap.
Critique: this is a design rule whose wrong implementation passes `check.sh`, with a red main as the result. The tempting fix is one allocate.spec case for `new`. But the publishing path reads the map through `read` (origin's), while the offline path and remap read other sources, and each is its own mutant.
Consequences: the fixture needs a map whose retired numbers sit just above the counter. It must stay an audit-clean tree, or allocate's other audit assertions change.
Recommendation: add cases and Rules rows, each run against the prototype with the mutant above split per call site:
- allocate.spec: origin has `tracker/next` `issue 90 …` and a `tracker/compaction.txt` whose old `c0010` and `f0091` are retired. `new issue c x` returns `c0092`, and origin's counter becomes 93. Offline (`PICKMAN_PUBLISH=0`, local map and counter only), it prints `c0092` and writes no counter. `renumber <id>` without `<new>` takes 92 the same way.
- remap.spec: set origin's counter after the compaction so that the branch's two items straddle a retired number. For example, seed an item numbered 4 so the map retires `c0004`, or make the branch hold three items. Assert the skipped number.
Mutants for the rows: "publishing path passes no map", "offline path passes no map", "remap passes no map", and "publishing path reads the local map instead of origin's" (origin's map exists, the local tree has none).

### F2 [medium] `tracker.sh sync`, which every skill runs first, is the plain merge the Compaction bullet forbids, and the stale-tree message recommends a merge first
Where: tracker skill "Sync first" ("`scripts/tracker.sh sync` in the worktree (a fetch and a merge of `origin/main`)", Sync and claim, and step 0 of Landing); make-issue step 0; ticket-prep "Sync first"; execute-raft step 1 and its final merge of `origin/main`. Prototype `cmd.sync`, which calls `mergeOrigin()` (`git merge --no-edit origin/main`, and on a conflict says `resolve it with: git merge origin/main`). Also `refuseStale`'s message `merge origin/main, or run tracker.sh remap on a branch that changed the tracker`. c0081's Compaction bullet: "run `tracker.sh remap` before merging `origin/main` … Never merge it plainly first".
Evidence: a prep or raft branch that was busy during a forced compaction resumes work. Its agent follows the skill and runs `tracker.sh sync` first, which is the plain merge. Or it runs `status`/`start`, gets refused, and the message offers "merge origin/main" before remap. What happens next depends on the branch:
- **The audit catches it.** The `retired-id` audit fires only when an item folder or a `raft:`/`issues:`/`depends_on:` token names a retired id. The way out is then "undo that merge", which `sync` itself just made.
- **The audit misses it.** A reference to an old id that is also a new id is excluded by design. Examples: `depends_on: [c0006]` on an emergent item, where old c0006 is now another item's number, or body text. Such references pass silently.
- **Merge conflict.** Template-like stubs pair wrongly under git's rename detection (c0081 E2). `sync` then aborts and tells the user to run `git merge origin/main` by hand, which is again the forbidden step.
So the rule the design depends on is contradicted by the command every skill makes the default first step.
Critique: the audit is a backstop for a mistake the tooling invites. Adding a sentence to the skill is the tempting fix, but agents run `sync` from four skills and from execute-raft's final merge, and none of them reads the Compaction bullet at that point.
Consequences: `sync` must know whether the branch is busy. Use the same test as `compact`'s busy refs: a non-empty `git diff --name-only $(git merge-base HEAD origin/main) HEAD -- tracker tests/acceptance`. A branch with no tracker changes still merges normally. `sync --fetch` and the main-checkout fast-forward are unchanged. `remap`'s own merge goes through `merge-tree`, not `mergeOrigin`, so it is unaffected.
Recommendation: in a worktree, when `origin/main` has a `tracker/compaction.txt` that differs from the local one, `sync`, and every `mergeOrigin` caller, does the following:
- On a busy branch: refuse with `this branch changed the tracker before the compaction on origin/main: run tracker.sh remap (it merges origin/main itself)`, and change nothing.
- On a branch that is not busy: merge as today.
Make `refuseStale`'s message use the same test and name exactly one way out. Spec cases in remap.spec:
- before `remap`, `tracker.sh sync` on the busy branch refuses, names `remap`, and leaves HEAD unchanged;
- a branch with no tracker changes cut before the compaction syncs cleanly and then publishes.
Add Rules rows for both, and a skill-doc case for one sentence in "Sync first": after a compaction, a busy branch's `sync` points to `remap`.

### F3 [low] An explicit `renumber <id> <new>` or `renumber <directory> <new>` can create a retired id, which the gate then rejects with a misleading message
Where: c0081 Allocation ("an explicit `<new>` is used as given and publishes nothing"); c0082 `cmd.renumber` (`<new>` used as given); c0082 `retired-id`.
Evidence: after the compaction, `tracker.sh renumber c0085 c0010` succeeds, because `c0010` is not in use. The next gate then fails with `retired-id tracker/issues/c0010: this tree mixes ids from before the compaction: undo the merge of origin/main and run tracker.sh remap`, and no merge happened.
Critique: the audit rule's claim that it "cannot fire on a sound tree" holds only for automatic allocation.
Consequences: none beyond one refusal.
Recommendation: refuse an explicit `<new>` that `ids.retiredIds` of the local map contains, with `<new> is retired by the compaction (tracker/compaction.txt): pick another number`. Add a cli.spec or allocate.spec case with a Rules row.

### F4 [low] Skipping about 80 retired numbers changes the user's "count by one" and is not listed for the user's review
Where: R0027 "Decisions this raft relies on" (the "Count by one, not by ten" quote; the prep decisions listed for the user's review); c0081 Solution (retired numbers skipped).
Evidence: after the compaction, new ids run `c0084 … c0089, c0091 … c0099, c0101 …` up to 890, a visible gap every ten. This was decided in refute 002 and is not among the prep decisions the report puts to the user.
Critique: the skip is a reasonable trade, but it changes a rule the user stated in their own words.
Consequences: none.
Recommendation: add it to R0027's prep decisions for the user's review: "after a compaction, allocation skips the numbers of retired ids (about 80, up to 890), so old references never name a new item".

### F5 [low] The stale-tree refusal lives in `main.luau`'s `publishFresh`, so R0025's new publishing commands (`ready`, `stop`, the `published()` wrapper) will bypass it unless someone remembers
Where: c0081 Solution ("in one helper called before `publish.commit`"); R0025.md line 95 (c0070 wraps every `publish.commit` call site, including new `ready` and `stop`, in `published()`).
Evidence: R0025 is prepped and touches the same call sites. Whichever raft merges second must add the other's wrapper to every site, and neither design mentions the other. A `ready`/`stop` that calls `publish.commit` directly publishes from a stale tree, which is review 002 F2's case.
Critique: one helper is right; the risk is a raft that does not know it exists.
Consequences: none beyond a note.
Recommendation: in c0081's Maintainability, name `publishFresh` as the only way to publish (remap excepted). Add a guard case to allocate.spec or compact.spec that greps `scripts/tracker/main.luau` for `publish.commit(` and allows only the wrapper and remap's call. A future direct call then fails the gate instead of relying on review.

### F6 [low] AC4 and its `check.sh` label still describe the round-1 behaviour
Where: c0081 AC4 ("a tree from before a compaction refuses to allocate"); c0081 check.sh AC4 label ("remap brings a busy branch onto the new ids so merging origin/main is clean").
Evidence: since round 2 the stale tree refuses every publish, not only allocation, and remap merges `origin/main` itself. remap.spec also checks that a plain merge fails the audit. None of this is in the criterion's text, so a reader of AC4 does not learn the rules the spec enforces.
Critique: clarity only. The spec is the real check.
Consequences: none.
Recommendation: AC4: "a tree from before a compaction refuses every publishing command (remap excepted); a plain merge of `origin/main` without remap fails the audit; `remap` …". Update the label to match (prep may still edit the sequestered file).

Verdict: changes

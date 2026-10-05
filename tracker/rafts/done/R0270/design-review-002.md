# Review 002: R0270 (design mode)
Inputs: prep worktree at 7c6fa30 plus its uncommitted prep edits (R0270.md, check.sh; c0870 and c0880 documents, check.sh, acceptance/*.spec.luau, experiments/prototype.diff); design-review-001.md and design-refute-001.md; prototype worktree proto-r0270 at e57069b (its ten new spec files are byte-identical to the prep ones); origin/main 515bd7e (`tracker.sh sync --fetch`: unchanged); the review, testing, ticket-prep and tracker skills. Experiments I ran, all in a scratch clone of proto-r0270 under the session scratchpad with a bare origin of its own: (1) `tracker.sh compact --force` in a worktree of that clone (83 issues, 27 rafts), then `scripts/check.sh --full` there: 1189 passed, 0 failed, which confirms E5 and the round-1 F2 fix; (2) status stamps and a code edit on main after the compaction's base, then a merge of the compaction branch: the stamps land on the renamed documents correctly; (3) a busy prep branch that merges the compaction with a plain `git merge`, without `remap` (F1 below).

Every round-1 answer holds. I checked each against the documents, the specs and the prototype:
- F1: next-file.spec keeps only "exists and parses"; RC3 is in R0270/check.sh; allocate.spec's emergent case pins the local counter as byte-identical and the audit's `next-behind` warning.
- F2: `renamed.id` is used in the rounds and repo-fence pins, and the trial compaction's gate is green (experiment 1).
- F3: `refuseStale` runs before every allocation, and remap.spec covers it.
- F4: `renumber <dir>` refuses a `done/` copy, and cli.spec covers it.
- F5: two unmapped items, and the counter is pinned at 5.
- F6: the direct-push exception names `tracker/next`, with a skill-doc case.
- F7: compact.spec covers audit in the main checkout, and the pre-audit exception is dropped.
- F8: the shim exception is recorded and the shim checks `{other}/.git` first.
No round-1 finding is repeated.

### F1 [medium] A branch that was busy during a forced compaction and merges `origin/main` without `remap` gets through: the merge is clean and the gate catches it only by accident
Where: c0870 `tracker.sh remap` ("For a branch that was busy during a forced compaction"); c0870 Solution ("A tree from before a compaction never allocates"); c0880 audit table; R0270 Risks ("A branch that must stay open uses `--force` … and `tracker.sh remap` on the branch").
Evidence: experiment 3. A branch was cut from e57069b. It appended a line to `tracker/issues/f0240/f0240.md`, added `tracker/issues/f0240/acceptance/new.spec.luau`, and added a new item `tracker/issues/c0900/c0900.md` whose text names `f0240`. A plain `git merge --no-edit trial` (the compaction commit) then **succeeded with no conflict**, with these results:
- The edited document followed its rename to `f0025/f0025.md`.
- `tracker/issues/f0240/acceptance/` was left behind under the old id.
- `c0900` kept its old-scheme number and its reference to the retired id `f0240`.
`tracker.sh audit` then reported `error no-document tracker/issues/f0240: no f0240.md` and `warning next-behind … not above 900`.
- The error is caught only because this branch happened to add a file inside an old item folder, and its message points the wrong way.
- A branch that only edits existing documents and adds items (an emergent issue whose `raft:` names its raft's old id, or a raft whose `issues:` lists old ids) merges cleanly. It produces only the `next-behind` warning and passes the gate, with membership references to ids that no longer exist or that now name other items (old `c0010`…`c0080` are reused by the compaction).
- `refuseStale` only blocks allocation. The merge itself is the step the design says must not happen before `remap`, and nothing enforces that.
- Clicking GitHub's "Update branch" or merging the PR runs exactly this plain merge.
Critique: `--force` is a supported path, and its safety rests entirely on a person remembering `remap` first. The tempting fix is to make `next-behind` an error after a compaction. That brings back round 1's F1, because the old-code terminals in R0270 Risks also cause it.
Consequences: after a plain merge the local `tracker/compaction.txt` equals origin's. So `remap` refuses ("this branch already has the compaction"), and the way out must be "undo the merge, then remap". An audit rule that reads the map also needs a precise definition of a retired id, so it never fires on the real compacted tree.
Recommendation: add an audit error `retired-id`. When `tracker/compaction.txt` exists, a retired id is one that is an old id in the map but not a new id in it. It is an error when it appears as an item folder's name, or as a whole token in an item document's `raft:`, `issues:` or `depends_on:` front matter. The message is "this tree mixes ids from before the compaction: undo the merge of origin/main and run tracker.sh remap". On the real tree this cannot fire: compaction rewrites every tracker `.md`, and old ids that are also new ids are excluded. Spec cases:
- audit.spec: a folder named with a retired id is an error; a front-matter reference to a retired id is an error; an id that is both old and new is not; nothing is checked without a map.
- remap.spec: before `remap`, a plain `git merge origin/main` on a copy of the busy branch makes `tracker.sh audit` fail naming `retired-id` and `remap`.
- A Rules and mutants row for each.
Also put the "never merge `origin/main` before `remap`" rule in the skill's Compaction bullet, with a skill-doc case.

### F2 [low] A tree from before a compaction can still publish status stamps; only allocation is guarded
Where: c0870 Solution ("every allocating command (`new`, emergent `new`, `new raft`, `renumber` without `<new>`) refuses"); prototype `main.luau`: `refuseStale` is called only at the three allocation sites, while `status <id> <to>`, `start` and the prep stamps also call `publish.commit`.
Evidence: these commands look up the id on origin/main. After the compaction, the old ids `c0010`…`c0080`, `f0010`…, `R0010` and `R0020` name *other* items (map: `c0050 c0006`, so origin's `c0050` is the old `c0500`). So `tracker.sh status c0050 …` from a stale tree stamps the wrong item, or is refused with a confusing transition error. In-flight ids are above the new range today, so they fail safely with "`<id>` is not on origin/main". That is why this is low. But that message doesn't say why, and the overlap grows as the new space fills.
Critique: the refusal exists so that a stale tree never acts on origin with old ids. Writing a stamp is such an action.
Consequences: `remap` itself publishes (its counter reservation) and must stay exempt, as now.
Recommendation: call `refuseStale` for every command that publishes, `remap` excepted. Placing it in one helper is the simplest way. Add a remap.spec case: before `remap`, `status <a mapped old id> preparing` on the stale branch refuses with the same message, and origin is unchanged. Add a Rules row.

### F3 [low] Risks says the only way `main` can move before the compaction PR merges is a conflict on `tracker/next`; other moves merge silently in the old scheme
Where: R0270 Risks ("If `main` moves first, the PR conflicts on `tracker/next`: reset to `origin/main` and run it again"); c0870 compact step 8.
Evidence: experiment 2. After the compaction's base, main took status stamps on f0230, f0240 and c0690 and a code edit. Merging the compaction branch was clean, and the stamps landed on f0024, f0025 and c0063, which is correct. So stamps are harmless. But a code or spec PR that lands in that window is never rewritten. For example, a new spec with a token-start `tests/acceptance/<old id>` path, or a real-id pin without `renamed`. Its references stay in the old scheme while the folders have moved, and nothing conflicts.
Critique: the procedure makes it sound as if a conflict will always flag a stale compaction.
Consequences: none beyond one procedural sentence.
Recommendation: in Risks and the skill's Compaction bullet, require that the compaction PR merges only while `origin/main` still equals the sha in `tracker/compaction.txt`'s header. If `origin/main` has moved at all, reset and run the compaction again; it is deterministic and cheap.

### F4 [low] The Regression guard says the skill states the "spell `tests/acceptance/` in two parts" rule, but neither the skill text nor any spec does, and spec authors are never told about `renamed.id`
Where: c0870 Regression guard ("the Compaction bullet in the skill states the rule"); the prototype's Compaction bullet in `.claude/skills/tracker/SKILL.md`; c0870 skill-doc.spec "a Compaction bullet …" (checks only `tracker.sh compact`, `--force`, `tracker.sh remap`, `tracker/compaction.txt`); `.claude/skills/testing/SKILL.md` (no mention).
Evidence: the prototype's bullet has no two-part spelling rule and no `renamed.id`. A spec written after this raft can do either of these:
- pin a real item id (as c0410/rounds did);
- name a promoted path as data.
Step 8's trial compaction cannot see such a spec, and the user's compaction then fails its gate. That is the Risks recovery path, and the rule would have prevented it.
Critique: spec writers read the testing skill, not the tracker's Compaction bullet.
Consequences: a new skill-doc case covers a skill that c0870 does not list as touched. So add the testing skill to Touched modules and check its Overrides: grep `tests/acceptance` for `testing/SKILL.md`.
Recommendation: add one sentence to the testing skill's spec-writing rules. Specs that pin real tracker ids go through `tests/lib/renamed.luau`, and test data naming a `tests/acceptance/<id>` path spells it in two parts. Add a skill-doc.spec case asserting `renamed` and the two-part rule there. Or drop the false claim from the Regression guard.

### F5 [low] Step 8's trial compaction cannot be run as written
Where: c0870 Implementation steps, step 8.
Evidence: the step runs `tracker.sh compact --force` in a fresh `git clone`. `compact` refuses in a main checkout (`refuseInMainCheckout`, which counts once the clone has an origin), and it needs `HEAD` to equal the bare origin's `main`. So the executor must push the branch to the bare origin as `main`, fetch, and run the compaction in `git worktree add … origin/main`.
I did exactly that. My first gate run then failed before any test ran, at the runner's identity tripwire ("this repository's git identity is a fixture identity … a check wrote it. Stop and report this"). The cause was that I had set `user.email` to an `@example.invalid` address in the clone's config so that `compact` could commit. An agent following the testing skill's fixture habit would do the same, then face a "stop and report" message about a repository that isn't the real one.
Critique: an executor who has never seen the repo would have to ask or guess.
Consequences: none.
Recommendation: spell the step out as commands:
1. `git clone --no-hardlinks . "$T/repo"`
2. `git clone --bare "$T/repo" "$T/origin.git"`
3. `git -C "$T/repo" remote set-url origin "$T/origin.git"`
4. `git -C "$T/repo" push origin HEAD:main && git -C "$T/repo" fetch --prune origin`
5. `git -C "$T/repo" worktree add "$T/repo/.worktree/trial" origin/main`
6. `tracker.sh compact --force` and `scripts/check.sh --full` in that worktree.
Add one rule: the commit identity comes from the environment or the global config, never from an `@example.invalid` entry in the clone's config.

Verdict: changes

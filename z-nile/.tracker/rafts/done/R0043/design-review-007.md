# Review 007: R0043 (design mode)
Inputs: origin/prep-z-nile-home at 33684ef. This is a re-review of the delta `git diff 1760273..33684ef`: c0114.md, R0043.md, the acceptance files docs, finished, finished.spec, registry, rewrites and window, the lesson no-live-counts-in-promoted-specs, and harvest.md. I checked it against the prototype `proto2-c0114` at 1f4afd2, in a scratch clone with no remote and `origin/main` set by `update-ref` to its merge base with origin/main. The prototype's c0114 acceptance files and check.sh are byte-identical to the prep's.
Dropped from design-review-006: F1, F2, F3, F4, F5, F6 (each one is fixed; the evidence is below).

Verified:
- **F1 (rewrites.FINISHED).**
  - The list has 122 paths, exactly the `done/` check.sh files on the prep branch, with no extras and none missing.
  - `unsettled` reads only that list.
  - Test 1 (later finishes keep the spec green): I placed c0114's own check.sh (which sources `scripts/lib/ac.sh`) under `z-nile/.tracker/issues/done/c0114/`, R0043's under `rafts/done/R0043/`, and R0034's (active, sources ac.sh, runs `scripts/check.sh`) under `tracker/rafts/done/R0034/`. Then I promoted finished.spec and rewrites into `tests/acceptance/c0114/` and ran `lune run tests/run.luau -- tests/acceptance/c0114/finished.spec.luau`. Result: **4 passed, 0 failed**.
  - Test 2 (the spec can still fail): I reverted one listed file (`done/c0035/check.sh`) to its base text. The spec failed with "still naming a moved path: z-nile/.tracker/issues/done/c0035/check.sh".
  - The fix holds.
- **F2 (the branch reserves no ids).** window.spec now runs `new issue`, `status` and `renumber` on the branch against a registry-less origin. Each one fails with "origin/main has no z-nile/projects.toml", and origin's tip and `tracker/next` are unchanged. window, registry and roots-cli on the prototype: 24 passed, 0 failed. `counterOf(hasNew, oldText)` matches the engine (`publish.luau:89`). There is one caveat about offline use: see F2 below.
- **F4 (no legacy-root defaults).**
  - `audit.scan` raises the registry problem. `audit.run` returns `error registry` before it scans.
  - `claims.taken`, `publish.allowed` and `trail.dirs` have no default.
  - Remap test: I made a fixture with a bare origin whose main has no `z-nile/projects.toml` and a changed `z-nile/compaction.txt`, plus a side worktree without the registry. There I ran `lune run z-nile/engine/main -- remap`. It exited 1 with "tracker remap: no z-nile/projects.toml in .: the tracker refuses to guess the project roots". It made no commit and left the tree clean.
  - remap commits before its scratch-worktree scan, so a later failure would leave a commit behind. That scan reads the merge base, which holds the registry whenever this engine runs, so the failure can't happen.
  - The specs the fix overrode pass on the prototype: c0053/publish, c0067/publish-move, c0084/spend-command and tests/tooling/claim-taken (63 passed, together with docs, finished and publish-roots).
- **The "list shows all projects" rule.**
  - It matches the user's decision as recorded in c0114 §2 and R0043.md.
  - `listedRoot` returns nil at the root, and `projectRoot` still refuses there for `new issue` and `new raft`.
  - No other command bypasses the refusal at the root:
    - An emergent issue takes its raft's root, and only in that raft's worktree.
    - `new raft` calls `projectRoot` before it does anything else, offline too.
    - `status`, `ready`, `stop`, `done`, `spend`, `renumber`, `compact` and `migrate` act on existing ids and keep their roots.
- **F3.** The "Sequestration in this PR" paragraph is in R0043.md and step 7a, and is narrow. The `':(exclude)*/done/*'` pathspec matches both roots' `done/` paths.
- **F5 and F6.** The §7 marker is now a decision. c0069's check.sh on the prototype: 6/6.
- No regression found in the delta. No guard is touched. The new fixture writes only `.cache/c0114-finished`.

### F1 [low] §3's list of rafts that "finish later and keep their old paths" contradicts step 9 for R0012 and R0041, and FINISHED is not "the files finished when c0114 lands"
Where: c0114 §3, the "Only items done at landing" paragraph; the `rewrites.FINISHED` comment; step 9 ("since the merge base")
Evidence:
- origin/main already has 128 `done/` check.sh files, against 122 on the prep branch. The six new ones are c0106, f0027, f0028, f0029, R0012 and R0041.
- §3 names R0012 and R0041 among the rafts that keep their old paths.
- But they finished before c0114 lands. So step 9 must rewrite them, and finished.luau, whose merge base is main's tip after the merge, requires `rewrites.expected` for them.
- Step 9's "since the merge base" is also ambiguous after the merge: the merge base is then main's tip. The set it means is the `done/` files at HEAD that are not in FINISHED.
- The outcome is still forced by finished.luau, so this is wording only.
Recommendation:
- Describe FINISHED as "the files finished at the prep's base".
- Drop R0012 and R0041 from the "later" list, or say "at prep time".
- Phrase step 9 as "every `done/` check.sh not in `rewrites.FINISHED`, other than c0114 and R0043".

### F2 [low] "`new issue` … and `renumber` all refuse on the branch" holds only while publishing; offline the branch still numbers locally
Where: c0114 §5 (no-registry bullet), §11 (ids in the window); window.spec's offline case
Evidence:
- window.spec itself pins that `new issue … --project pickman` with `PICKMAN_PUBLISH=0` succeeds on the branch. It writes `tracker/issues/c0064` from the local `tracker/next`, which is the same number main's next capture gets.
- The tracker skill documents `PICKMAN_PUBLISH=0` as the way to work locally. The publish failure message even suggests it: "(PICKMAN_PUBLISH=0 creates it locally instead)".
- An executor who takes that hint makes a colliding id. `renumber` then refuses online, so the branch can't repair the collision. `audit` after the merge would show it.
Recommendation: in §11, say that offline captures on the branch are forbidden in the window, and that captures go to the main checkout. Alternatively, have that refusal message not suggest `PICKMAN_PUBLISH=0` when origin has no registry. The fixture case can stay, since it proves the local counter is read.

### F3 [low] The pinned wording "the commands that create or change a project's items (`new issue`, `new raft`) refuse" is wrong for change commands
Where: c0114 §2 and Decisions item 11; the tracker skill's Projects bullet (pinned by docs.spec)
Evidence:
- `status`, `ready`, `stop`, `done`, `spend` and `renumber` change items, yet they run at the root and must keep doing so: the skills run them from the main checkout.
- Only the two commands that create an item, and so must choose its project, refuse.
- A future reader of the pinned sentence could make `status` refuse at the root.
Recommendation: reword the sentence in all three places (the specs' quoted text included) to "the commands that create an item, and so must choose its project (`new issue`, `new raft`)".

### F4 [low] Stale leftovers
Where:
- c0114 §5: "`publish.counterOf(hasRegistry, hasNew, oldText)`". The engine and window.spec take `(hasNew, oldText)`.
- The `publish.allowed` row: "(roots required, no default) … under one of `roots` (default the legacy root alone)".
- The §7 jail bullet: "accepted as guessed (…). this jail exception, …" is a sentence fragment.
- c0069 AC6's label still reads "c0053's replacement copy still matches". After the special edit it checks only that the copy exists.
Recommendation:
- Fix the three prose lines.
- The label is in a sequestered finished file, so either add it to the c0069 special edit or leave it and note it in the Verification log.

Verdict: approve

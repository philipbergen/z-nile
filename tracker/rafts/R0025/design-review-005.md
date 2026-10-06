# Review 005: R0025 (design mode)
Inputs: f3bd2ab (clean tree). Reviewed: R0025.md and check.sh; c0062, c0066 and c0071 in full (documents, check.sh, c0066's spec); c0067–c0070 check.sh files and specs against R0021's rules; c0069's Overrides; `git diff origin/main -- tracker/issues/done tests/acceptance .github`; design-review-004 and design-refute-004. R0021 is taken as `origin/R0021-check-isolation` (d6ec749): `tests/tooling/repo-fence.spec.luau`, `tests/lib/fixture.luau`, `scripts/lib/fence.sh`, the testing skill, c0059's `adapt.spec` and check.sh, c0060's `retrofit.spec` and check.sh, c0058's check.sh, and `tests/acceptance/c0053/commands.spec.luau` as R0021 leaves it.
Dropped from review-004: none outright. F2–F6 are fixed as design-refute-004 states: the grouping is written down, c0066 has the breadth-first listing, the retry rule and its spec case, step 5.5 is rewritten, step 7's texts are listed, and AC2 bans `refute-003`. F1's ordering, conversion and Overrides are fixed. Its new checks bring the new F1 below.

What I ran, all in a scratch clone under `$TMPDIR` (`r5merge`): this prep merged with `origin/R0021-check-isolation`, with no conflicts.
- **repo-fence.spec in the merged clone.** "no spec, check.sh or script switches a guard off" fails on this prep's own files, listed in F1. The jail case also fails, but only because the clone sits in `$TMPDIR`, so that failure doesn't count.
- **All member specs in the merged clone.** Every setup case passes except c0069's, which needs `ready`. Every other failure is a command or module this raft creates.
- **The c0005 replacement.** `cmp` of the merged `tests/acceptance/c0005/worktree.spec.luau` against `tracker/issues/done/c0053/replacements/c0005-worktree.spec.luau` differs at line 8 (F2).
- **Two probe specs cut from the R0021 version of commands.spec**, each with its own `.cache` folder:
  - setup, then the `commands-new` cases up to "an id taken…", then the frozen `commands-claim` group in order: the first 10 cases pass and 4 fail (F3);
  - setup and the four cases that share `zeta`/`rz`, plus "an existing draft raft…": 5 of 5 pass.
- **Identities and fixture folders.** A grep finds only `@example.invalid` identities. Each member spec uses its own `.cache/<dir>`.

### F1 [high] Two of this prep's own check.sh files name the words R0021's gate scan bans, so the full gate goes red once both rafts are on main, and RC0 and c0062's AC5 can't pass
Where: `tracker/rafts/R0025/check.sh:81-82` (RC8's `grep -e GIT_CEILING_DIRECTORIES -e GIT_DIR …`); `tracker/issues/c0062/check.sh:69` (`grep -l "GIT_INDEX_FILE"`); R0021's `tests/tooling/repo-fence.spec.luau`, `sources()` (it scans every `check.sh` under `tracker/`, in any lifecycle folder) and `ALLOWED` (no entry for either file).
Evidence: in the merged clone, `lune run tests/run -- tests/tooling/repo-fence.spec.luau` prints:
```
FAIL … :: no spec, check.sh or script switches a guard off or points git elsewhere
  tracker/rafts/R0025/check.sh names GIT_CEILING_DIRECTORIES
  tracker/rafts/R0025/check.sh names GIT_DIR
  … (also GIT_WORK_TREE, GIT_INDEX_FILE, GIT_COMMON_DIR, GIT_CONFIG_, hooksPath, --no-verify, env -i, sandbox-exec, GH_CONFIG_DIR, GIT_SSH_COMMAND)
  tracker/issues/c0062/check.sh names GIT_INDEX_FILE
```
The consequences:
- **This raft's checks can't pass.** RC0 (`scripts/check.sh --full`) runs this spec. So does c0062's AC5, directly. Both files are sequestered, so no correct implementation passes them.
- **R0021 breaks too.** If the prep PR merges before R0021 lands, R0021's own full gate goes red when it merges `origin/main`. It is then blocked by another raft's sequestered file.
- **The author knew the rule.** RC7's `no_index` splits the name (`"GIT_INDEX_""FILE"`) and says "R0021's gate scans every check.sh". RC8 and AC5, added in round 4, don't split theirs.
- **RC8's list is incomplete.** It has 14 hand-copied names. R0021's `NAMES` has 32, so RC8 misses `PICKMAN_TEST_FENCE`, `PICKMAN_FENCE_`, `GIT_OBJECT_DIRECTORY`, `osascript`, `launchctl`, `protocol.*`, `credential.`, `extraheader`, `GIT_ASKPASS`, `SSH_ASKPASS`, `GIT_ALLOW_PROTOCOL`, `_proxy`, `http.proxy` and `gitproxy`. It can pass a spec that the scan then fails once the spec is promoted.

Critique: the tempting fix is to split every literal with `""` concatenation, as RC7 does. That fixes the scan for these two files. It keeps RC8's list a stale copy of R0021's, though, and every later edit to `NAMES` widens the gap without anyone noticing.
Consequences: RC8 then depends on `tests/tooling/repo-fence.spec.luau` existing. That holds, because R0025 can't start until R0021 is done (c0067's and c0062's `depends_on`). It also needs a guard for the case where reading the list silently yields nothing. And whatever the prep adds to a `check.sh` from now on has to pass the scan itself.
Recommendation (all in prep, since both files are sequestered):
- **RC8** reads the banned list at run time from the spec it mirrors, and fails if the list comes back empty. For example: `names=$(sed -n '/^local NAMES = {/,/^}/p' tests/tooling/repo-fence.spec.luau | grep -o '"[^"]*"' | tr -d '"')`, then `[ -n "$names" ] || { echo "no NAMES in repo-fence.spec"; exit 1; }`, then `grep -rniF` over each member's `acceptance/` with one `-e` per name. Keep the shell-string patterns (`"sh", { "-c"`, `process.create`) as they are; the scan does not ban them.
- **c0062 AC5** splits the literal: `grep -l "GIT_INDEX_""FILE"`.
- **Verification**: in a scratch merge with `origin/R0021-check-isolation`, run `tests/tooling/repo-fence.spec.luau` and confirm that its scan case lists none of this raft's files. Record that in R0025's Experiments phase as a prep result.

### F2 [high] After R0021, the promoted c0005 no longer equals c0053's replacement copy, so RC6 and c0069's AC6 fail, and no document says to recopy it
Where: R0025 RC6 (`cmp -s "$R/c0005-worktree.spec.luau" tests/acceptance/c0005/worktree.spec.luau`); c0069 `check.sh` AC6 (the same `cmp`); c0069 Overrides, "Done in prep" (the replacement "is rewritten to match it byte for byte"); R0021's c0058 Override (c0058.md: the promoted c0005 drops its `NO_GC` `GIT_CONFIG_*` injection and goes through `@tests/lib/fixture`); `tracker/issues/done/c0053/check.sh` AC8.
Evidence: R0021's branch changes `tests/acceptance/c0005/worktree.spec.luau` in 31 lines (`require("@tests/lib/fixture")`, an empty `NO_GC`, `fixture.exec`). It doesn't touch `tracker/issues/done/c0053/replacements/c0005-worktree.spec.luau` (`git diff --stat origin/main origin/R0021-check-isolation` lists no `replacements` path). This prep edits both files in the same hunk (the prompt case at line 219), and git merges that cleanly. After the merge, `cmp` reports `differ: char 496, line 8`.
R0025 starts only after R0021 is done and has merged `origin/main`, so the sequestered RC6 and c0069 AC6 fail for a correct implementation. The fix is a write to a done item's non-sequestered file. Neither c0069's Overrides, R0025's "Done in prep" nor the Risks bullet on R0021 names it, so the executor must either guess that it is allowed or stop. (R0021 also turns c0053's own AC8 red on `main`. That is R0021's regression, but RC6 copies the same check.)
Critique: the tempting fix is to recopy the replacement now, in prep. It can't be done yet: R0021's c0005 is not on `main`, and copying from its branch would make the prep's checks fail until R0021 merges.
Consequences: the replacement then copies R0021's c0005, so it holds R0021's fixture conversion and this prep's narrowed prompt case. The recopy runs in execution, after R0021 is merged in, on a done item's file. A done item's replacement file is outside the sequestration diff (`check.sh` and `acceptance/` only), but rewriting it has to be named as an Override, like any edit to a promoted spec.
Recommendation:
- **c0069 Overrides, "In execution"**: "After merging `origin/main` with R0021, copy `tests/acceptance/c0005/worktree.spec.luau` over `tracker/issues/done/c0053/replacements/c0005-worktree.spec.luau` if they differ (R0021's c0058 Override changed the promoted c0005 and not the replacement), so c0053's AC8, RC6 and this issue's AC6 hold."
- **R0025 Risks (the R0021 bullet)**: add the same sentence, so the executor sees it before Phase 1.
- **Escalate to the user**: R0021's open PR leaves c0053's done AC8 red on its own. Its executor could recopy the replacement before landing it, which would make this step a no-op.

### F3 [medium] The frozen `commands-claim` group fails when run in order: "a move to prepared…" leaves `cap` dirty, and "a published move abandons prep…" then can't run `new raft`
Where: c0062 Design, "Grouping, frozen", group 2; R0021's `commands.spec.luau` "a move to prepared is carried by the PR…" (it writes `design: ready` into `cap`'s c0240 and runs a local-only `status c0240 prepared`, all uncommitted); "a published move abandons prep…" (`trOk(cap, { "new", "raft", … })`); `scripts/tracker/main.luau` `new raft` (`working tree is not clean` when publishing).
Evidence:
- **In the original order a later case cleans up.** "a prepared raft starts once" (group 3 now) commits `cap`'s edits ("tracker: prep R0001") before "abandons prep" runs.
- **In the frozen group nothing does.** My probe ran setup, the new-group cases up to "an id taken", then the claim group in its frozen order. It failed `a published move abandons prep … : tracker.sh new raft chore zraft c0310 --single failed (1): working tree is not clean`. The three cases that follow fail with it, because they share `zeta`/`rz`.
- **Reordering inside the part doesn't help.** "new raft claims" and "status lists" assert the literal ids `c0240`, `c0250` and `R0001`. If `zeta` or `rz` were created first, they would take those numbers.
- **A fifth part works.** The four cases "a published move abandons prep…", "a raft move follows the local member list…", "new issue refuses --raft…" and "an existing draft raft is claimed…" pass 5/5 alone after a plain setup. They need no earlier state.
- **The `commands-start` seed is described wrong.** Its example ("seeds a prepared raft R0001 … design ready") contradicts the case it feeds. "a prepared raft starts once" itself runs `status R0001 prepared`, a move that origin accepts only from `preparing` (`canMove`). So the seed must leave R0001 and c0240 `preparing` on origin, with c0240 listed locally in R0001's `issues:`.

E1's fallback ("split a part further") would get an executor there. But the document says "frozen", and the error is known now.
Recommendation: replace the grouping with five parts. AC2 needs four or more, so `check.sh` doesn't change.
- `commands-claim`: "new raft claims…", "status lists…", "a status move refuses…", "a move to prepared…", "a move is checked against origin…".
- `commands-prep` (new; `sets up the prep fixture`): "a published move abandons prep…", "a raft move follows…", "new issue refuses --raft…", "an existing draft raft is claimed…".
- Correct the `commands-start` seed: R0001 (`issues: [c0240]`) and c0240 are both `preparing` (stamped) on origin, designs `draft`, and the raft is reachable from `cap` and `main`. The case itself does the move to `prepared`.
- Seeds that must reproduce literal ids say so: `commands-claim` seeds c-issues up to c0230, so `new issue` returns c0240 and c0250.
- In E1, record each part passing alone and all of them passing together.

### F4 [medium] Two c0053 cases can't follow the fixture rule that c0062 adopts, and the design doesn't say what they do instead
Where: c0062 Design (`trackerfix` "git and `tracker.sh` calls go through `fixture.git`/`fixture.exec` … Raw git only for `init` and `clone`"); R0021's testing skill, Fixtures ("Run git and `tracker.sh` in a fixture only through `@tests/lib/fixture` … no shell strings (`sh -c`), no `process.create`", and c0053's specs "convert them when they are next edited"); `tests/lib/fixture.luau` `fixture.check`; commands.spec "a tracker command in a directory that lost its .git…" and "stamps from processes started together differ…".
Evidence:
- **The lost-`.git` case can't go through the helper.** It runs `tracker.sh` in `{base}/outer/wt/lost`, a directory that deliberately has no repository of its own. `fixture.check` resolves `git rev-parse --show-toplevel` to `outer/wt`, not `lost`, and raises "refusing to run … not a fixture repository" before `tracker.sh` starts. So `trackerfix.tr(f, lost, …)` raises instead of returning the refusal the case asserts (`repository root` in stderr, 22 commands). That refusal is the point of the case.
- **The stamps case needs a shell string.** It starts three `tracker.sh stamp new` at once with `process.exec("bash", { "-c", "cd … && (… & … & … & wait)" })`. That is exactly the shell string the rule bans. It has no stated replacement, and running `fixture.exec` concurrently through `task.spawn` is unproven: nobody has checked that Lune's `process.exec` yields.

c0062 converts c0053's spec, and the skill says to convert on the next edit. So the executor finds two cases the rule can't express, and no exception is recorded for either. A code reviewer would then flag whatever choice is made.
Recommendation:
- **c0062 Design**: name both cases as exceptions with their reasons, and say how each runs.
  - The lost-`.git` case runs `tracker.sh` with raw `process.exec` in `lost`, because no fixture repository is the point. It still writes nothing outside `{base}`, and `fixture.git` builds `outer`.
  - The stamps case either keeps one `bash -c`, the only one in the part, with the reason given in a comment, or uses a stated alternative.
- **Experiment**: add E3. Do three `task.spawn`ed `fixture.exec` calls overlap? Pass when their wall time is under 2× one call. Fallback: the commented `bash -c`.
- **Rules and mutants**: add a row for "a command in a `.git`-less directory is refused, not run in the enclosing repository", killed by the lost-`.git` case running through `fixture.exec`. That mutant makes the case error out instead of asserting.

Verdict: changes

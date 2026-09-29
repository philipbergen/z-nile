# Review 002: R0010 (code mode)
Inputs: HEAD 26f0b02 (R0010-foundation, clone at ~/code/pickman) against main, start commit 25af492. I read review-001 and refute-001 first. The focus is the delta 9f451ba..26f0b02: tests/lib/place.luau, tests/place/resolver.spec.luau, scripts/affected.luau, .github/workflows/check.yml, and the c0020, c0040, R0010 and c0050 docs.

Commands run (all in ~/code/pickman; `git fsck` is clean):
- `scripts/check.sh --full`: GATE PASSED, 30 passed, 0 failed, 6 spec files.
- `scripts/tracker.sh check c0020`: 3/3.
- `scripts/tracker.sh check c0040`: 1/1.
- c0010 specs (`lune run tests/run -- tracker/issues/active/c0010/acceptance/*.spec.luau`): 15 passed, 0 failed, 2 spec files. F1's failure no longer reproduces.
- `scripts/tracker.sh promote-check R0010`: OK (8 passed).
- Sequestration: `git diff -M 25af492 -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` shows only two new files:
  - `tracker/issues/active/c0040/check.sh`: emergent, which is allowed.
  - `tracker/issues/c0050/check.sh`: an unfilled template for a backlog item that isn't in this raft.
  No R0010, c0010 or c0020 check file or acceptance spec changed. **Sequestration: clean.**
- `gh run list --workflow check.yml --limit 3`: the two runs on 26f0b02 are `pull_request` runs, skipped because the PR is a draft. So the new `permissions: contents: read` block has not run on CI yet. c0010's check (ci-verify) will exercise it at `done`, and nothing setup.sh or the gate does needs more than read.

## Re-review of review-001
- **F1**: dropped. Work continues from a clean clone outside iCloud. fsck is clean, the c0010 specs pass 15/15 locally, and the follow-up is filed as c0050.
- **F2**: dropped. `resolveRequire` now returns nil for an empty rest, for empty and `.` segments, and for `..` after a named segment or after `./` or `@self/`. I traced the old code against `tests/place/resolver.spec.luau`: `@self` returned Maze, `./Data//Level1` returned Level1, and `./../Movement` returned Movement, so the "failed 3/3 before the fix" claim holds. The negative cases share their tree with c0020's `resolve-require.spec.luau`, which keeps the positive controls (`./Data/Level1`, `../../Movement`, `@self/Data/Level1`), so the nils can't come from a resolver that rejects everything. The stricter rule on `./..` can only produce false failures, never false passes, which is the safe direction for an oracle.
- **F3**: dropped. The build goes to `.cache/place-test-<os.time()>-<math.random>.rbxl` and the file is removed after `deserializePlace`, whether it succeeds or fails. I checked that Lune seeds `math.random` per process: three runs in the same second gave 338494728, 509739418 and 598354750. No `place-test*` files were left in `.cache` after the gate. The change is recorded as a deviation in c0020.
- **F4**: dropped as a defect, because the fix is correct: both `git diff --name-only` calls now pass `--no-renames`. I also checked that `lune run scripts/affected -- src/shared/Gone.luau`, a deleted src path, selects both place specs without erroring. The fix has no test; see F1 below.
- **F5**: dropped. There is a workflow-level `permissions: contents: read`.
- **F6**: dropped. c0040 is listed under "Addressed during execution" with its reason. The understated spend and AC1's host-dependence are recorded in c0040's log.

### F1 [low] The `--no-renames` fix (review-001 F4) has no regression test
Where: scripts/affected.luau:47-49; tests/tooling/affected.spec.luau
Evidence: `tests/tooling/affected.spec.luau` exercises only explicit file lists and `graph.affectedSpecs`, never `changedFiles`. If a refactor drops `--no-renames`, the gate stays green, and moving `src/shared/Foo.luau` out of `src/` would again select no place specs.
Fix: add a tooling case that builds a throwaway git repo in a temp dir (outside the worktree; see c0050) with a commit that renames `src/X.luau` to `tests/fixtures/X.luau`. Assert that `affected -- --base HEAD~1` includes the place specs. Alternatively, file it as a backlog chore.

### F2 [low] c0050's Solution files a "defect" for a test fix, which contradicts the testing skill
Where: tracker/issues/c0050/c0050-lifecycle-spec-clone-isolation.md, Solution, first bullet
Evidence: "File a defect against the promoted spec". The testing skill says of promoted specs: "if one is wrong, file a chore (test fixes are always chores)". The tracker and make-issue skills say the same: every CI/test/tooling fix is a chore. Filing it as a defect would skew the rework metric. Besides, c0050 is itself a chore, so it can just make the change when it's prepped instead of filing another issue.
Fix: change it to "fix the promoted spec in this chore" (or "file a chore"). The doc is `design: draft`, so ticket-prep can settle this.

## Judged criteria (code mode only)
None. c0010, c0020 and c0040 define no Judged criteria.

Design adherence: the delta matches c0020's Design, and the one new deviation (the per-process build path) is recorded with a reason. There are no src/ changes, so there are no architecture or performance concerns.

Verdict: approve

# Review 001: R0001 (code mode)
Inputs: HEAD 9f451ba (R0001-foundation) against main e4c21b2, start commit 25af492. Files: `git diff main...HEAD`, R0001-foundation.md and check.sh, c0001, c0002 and c0004 docs and check.sh, the c0001 and c0002 acceptance specs. CI run 36516563662 (workflow_dispatch, headSha 9f451ba, success: gate 27/27, acceptance step 31/31 across 5 spec files).

Commands run:
- `scripts/check.sh --full` (local): GATE PASSED, 27/27.
- `scripts/tracker.sh check c0002`: 3/3. `scripts/tracker.sh check c0004`: 1/1 (host `bash` is /bin/bash 3.2.57).
- c0001 specs (`lune run tests/run -- …tracker-lifecycle… …ci-workflow…`): **6 passed, 9 failed in the local checkout**, and **15/15 in a fresh clone of origin/R0001-foundation**. See F1.
- Sequestration: `git diff -M 25af492 -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` fails locally ("unable to read tree"). In the fresh clone it shows only the new `tracker/issues/active/c0004/check.sh` (emergent issue, allowed); every c0001, c0002 and R0001 check.sh and acceptance spec is a 100% rename. **Sequestration: clean.**
- In the fresh clone: `scripts/tracker.sh promote-check R0001` gives OK (RC2), and the place tier gives 3 passed, 0 failed, 1 spec file (RC1).

### F1 [high] The local repository's object store is corrupt, so c0001 AC1 (and therefore R0001 RC0 and `tracker.sh done`) fails on this host
Where: `/Users/philipbergen/Documents/code/AI/pickman/.git` (an iCloud Drive-synced `~/Documents` path: `xattr ~/Documents` shows `com.apple.CloudDocs.iCloudDriveFileProvider`)
Evidence:
- `git diff 25af492 -- tracker/...` fails with `fatal: unable to read tree (4e1f39fc…)`. A later retry fails on a different tree (`d249bf2c…`, the start commit's `tracker/rafts`), so objects are appearing and disappearing while I work.
- `git fsck` reports 95 `bad sha1 file: … 2` iCloud conflict copies, plus `.git/index 2`, broken tree links and invalid cache-tree pointers in both worktrees' indexes.
- `git clone <repo>` completes, but its checkout fails ("retry with git restore"). So the lifecycle spec's throwaway clone has no `scripts/tracker.sh`, and 9 cases fail with `bash: scripts/tracker.sh: No such file or directory` / `os error 2`.
- The lifecycle spec's local `git clone` hardlinks object files into `.cache/tracker-e2e/.git/objects` (same inodes, link counts 4 to 6), which is also inside the synced tree. That makes it worse.
- The verification log's "tracker.sh check c0001 gave 5/5" does not reproduce here. The code itself is fine: 15/15 in a clean clone, and green on CI.
Fix: no code change. Stop committing from this working copy.
1. Disable Documents sync for it, or move the work outside `~/Documents` (for example `~/code/pickman`).
2. Re-clone from origin, which has every commit through 9f451ba and fscks clean.
3. Re-run R0001's check.sh from there before `tracker.sh done`.
4. File a backlog chore: the lifecycle spec should clone with `--no-hardlinks` into a temp dir outside the worktree (the spec is sequestered, so don't edit it in this raft), and SETUP.md troubleshooting should warn against cloud-synced checkouts.

### F2 [low] `resolveRequire` accepts malformed specs that Roblox is unlikely to accept, and nothing pins its rejection behavior
Where: tests/lib/place.luau:62-87
Evidence (probed on a synthetic tree):
- `resolveRequire(maze, "@self")` returns Maze itself, a self-require.
- `resolveRequire(grid, "./")` returns its Parent.
- `"./Maze//Grid"`, `"./Maze/./Grid"` and `"./../Movement"` all resolve.
place-rules uses this function as the Roblox oracle, so a spec like these that Lune also tolerates would pass AC2 and fail in Studio. E3 is already an accepted risk, but these cases go beyond the documented semantics.
Fix: return nil when `rest` is empty, on empty segments, and on `.` segments. Add those negative cases to a `tests/place` or tooling spec.

### F3 [low] `place.load()` builds to a fixed shared path, so concurrent test processes race
Where: tests/lib/place.luau:13,28-32
Evidence: `OUT = ".cache/place-test.rbxl"` is written by `rojo build` and read back in each process. If two processes run at once (the Claude Code stop hook's `check.sh --affected` while an agent runs `tracker.sh check`, or two gates), one can deserialize a partially written file and fail spuriously.
Fix: build to a per-process name (for example include `os.clock()`/a random suffix, or build to a temp name and rename), and delete it after reading.

### F4 [low] Changed-file detection loses the source path of renames, so moving a file out of `src/` does not select place specs
Where: scripts/affected.luau `changedFiles` (pre-existing), relied on by the new `graph.affectedSpecs` place rule (scripts/lib/graph.luau:218-229)
Evidence: `git diff --name-only` uses rename detection by default and prints only the destination. Moving `src/shared/Foo.luau` to `tests/fixtures/Foo.luau` yields only `tests/fixtures/Foo.luau`, so `placeChanged` stays false even though the DataModel lost a ModuleScript.
Fix: pass `--no-renames` to both `git diff --name-only` calls in `changedFiles`.

### F5 [low] check.yml exposes a default-permission token to the whole test suite
Where: .github/workflows/check.yml:19-22
Evidence: `GH_TOKEN: ${{ github.token }}` is set on the `scripts/setup.sh` step, which runs `scripts/check.sh --full`, so every spec (including branch code) inherits it. The workflow has no `permissions:` block, so the token has the repo default, which may be read/write. setup.sh needs only `gh api rate_limit`, `gh release download` from a public repo, and rokit downloads.
Fix: add `permissions: { contents: read }` at the workflow level.

### F6 [low] c0004 is not recorded on the raft, and its regression check only discriminates where `bash` on PATH is 3.2
Where: tracker/rafts/active/R0001/R0001-foundation.md "Addressed during execution" (empty); tracker/issues/active/c0004/check.sh:6
Evidence:
- The tracker skill requires emergent issues to be listed under the raft's "Addressed during execution". The section is empty.
- `check "AC1: …" bash scripts/check.sh --affected` passes without the fix on bash ≥ 4.4 (CI, or a Mac with Homebrew bash first on PATH). It is only a real guard on this host.
- c0004's spend (0.1 min) hides its diagnosis time inside c0002's 24.9 min, which understates rework.
Fix: list c0004 under "Addressed during execution" with a one-line reason. In future emergent checks, prefer `/bin/bash` explicitly when the target is macOS system bash.

## Judged criteria (code mode only)
None. c0001, c0002 and c0004 define no Judged criteria.

Design adherence: check.yml, setup.sh (CI auth, `rokit authenticate --skip-parse --skip-verify`, `GITHUB_PATH`), ci-verify.sh (steps 1-5, including the `databaseId > before && headSha == HEAD` filter), place.luau's API, `graph.PLACE_LIB`, the `affectedSpecs` extension, the structure spec and the docs all match the designs. The one deviation, `graph.REQUIRE_PATTERN` exported and reused by `place.requireSpecs`, is recorded with a reason and is an improvement. The bare-spec nil behavior is recorded. E1 and E3 results are recorded against run 36516452734. No src/ changes, so there are no architecture or performance concerns.

Verdict: changes

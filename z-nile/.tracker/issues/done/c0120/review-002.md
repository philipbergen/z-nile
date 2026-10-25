# Review 002: c0120 (code mode)
Inputs: `impl-c0120` at 9e91723 (fix delta `429e248..HEAD`: 2350b12 fence fix, 9fad9b7 merge of prep's 98b5154, 9e91723 refute and log), `git diff origin/prep-c0120...HEAD` (origin/prep-c0120 at 98b5154), review-001 and refute-001, c0120.md, `./zn lessons --when build --full`. Runs: `z-nile/check.sh --full` GATE PASSED (pickman 1068/157, z-nile 829/119, 85.3 s). `bash z-nile/.tracker/issues/c0120/check.sh`: 14/17. Sequestration against origin/prep-c0120 over the item roots' `check.sh` and `acceptance/`: 103 files, all R100. Scratch reproductions in `/private/tmp/claude-501/-Users-philipbergen-code-pickman/de5efc35-2bcd-47ee-b2a5-bc31e5be44c7/scratchpad/code-review-c0120-002/` (clone of 9e91723, `probe.sh`, `fence-old.sh` = 429e248's fence, `fence-mut.sh`).
Dropped from review-001: F1, F2, F3 (all fixed; F1 verified below).

Review-001 F1 is fixed. `probe.sh` sources a fence, runs `pickman_fence "$PWD" specs` from a folder, prints `PICKMAN_FENCE_REAL_GIT`, and tries `git update-ref` in the clone. With 429e248's fence: `GIT_DIR=.git` from `pickman/` gives `REAL=::` and ESCAPED, and `GIT_DIR=<foreign>/.git` from the root records the foreign repository and ESCAPED. With 9e91723's fence both record the clone's `.git` and REFUSED. So do `GIT_COMMON_DIR=<foreign>`, and the clean run.

Prep's new `homes.spec` cases (98b5154, merged as 9fad9b7) were a legitimate addition. The raft isn't readied, so its acceptance specs are still prep material. They were added on the prep branch, not on the build branch, and the build branch only merged them. They are additive (two cases, no existing case changed), they are recorded in the Rules table (W7) and the Verification log, and this round reviews them. The sequestration diff against prep is all R100.

### F1 [high] An inherited `GIT_CEILING_DIRECTORIES` that names the checkout's root still leaves a run from `pickman/` with no ref guard and a blind tripwire
Where: `z-nile/lib/fence.sh:82` (`real=$(git -C "$here" rev-parse … --git-common-dir)`). The same blind spot is in `tests/lib/fence.luau`'s `git()` (`OVERRIDES` doesn't list the ceiling), which `protectedPaths` and `snapshot` use.
Evidence: run in the scratch clone.
- `env GIT_CEILING_DIRECTORIES=<clone> bash probe.sh <clone> <clone>/z-nile/lib/fence.sh pickman` prints `REAL=::`, then ESCAPED: `git update-ref refs/heads/evil-002 HEAD` succeeds in the clone. 429e248's fence does the same.
- The real runner does it too. `cd <clone>/pickman && GIT_CEILING_DIRECTORIES=<clone> lune run tests/run -- <a probe spec>` runs, and the spec sees `PICKMAN_FENCE_REAL_GIT` empty. The same run without the variable sees `<clone>/.git`.
- Why: git never searches up *into* a ceiling folder, though it always searches the folder it starts in. From the root, the fence's read is immune: c0114's fence always started there. From a home it must go up one level, and a ceiling at the root stops it. So the hole is new with c0120's home runs.
- The fence derives `real` from that read and fails open when the read finds nothing. The `reference-transaction` hook passes every update when `PICKMAN_FENCE_REAL_GIT` is empty. A spec's explicit `git -C <root> …` still finds the real repository, because git always searches the folder it starts in.
- On Linux (CI, no jail) the hooks are the only guard, so a spec run by `(cd pickman && lune run tests/run)` can then update the real refs. The tripwire's `snapshot` and `protectedPaths` also read nothing, because the runner's `git()` keeps the inherited ceiling.
- A side effect: `pickman_guarded <root>` answers `unguarded` in such a run, so a tracker command a spec starts at the root would publish. It would fail at the network guard, but only after its local commit and ref update.
- On macOS the jail's `(deny file-write* (subpath "/"))` still holds, whatever `protectedPaths` returns.
- The variable is rarely set by hand. But the testing skill states the guarantee without a condition ("ignores inherited repository overrides"), and the skill's own rule is that any path to the real repository is high.
Critique: this is the second hole in one mechanism. The fence derives the protected repository from one discovery read, and treats "found nothing" as "protect nothing". Round 1's hole was an override that redirected that read. This one is an override that makes it fail. The tempting fix is to add `GIT_CEILING_DIRECTORIES` to the `unset` line. That breaks the fence's own accumulation: nested fences must keep the outer `<checkout>/.cache` ceilings, and the specs need them.
Consequences: making the read itself independent of the ceiling (`env -u GIT_CEILING_DIRECTORIES git -C "$here" …` for that one read only) leaves the specs' ceiling intact. Without the ceiling, discovery can only find more: inside a `.cache` fixture with no repository, the read stops at the sentinel `.cache/.git` (`gitdir: /nonexistent`) and fails as before, or, where the jail refused the sentinel, it reaches the real repository and protects it. Both are safe. The runner side needs the same: `fence.luau`'s `git()` is used for `protectedPaths`, `snapshot` and the worktree list, and each of these wants the real checkout. A case that names `GIT_CEILING_DIRECTORIES` needs a repo-fence `ALLOWED` entry, like this round's `GIT_DIR` entry.
Recommendation:
- Question the fail-open as well as the read. In `pickman_fence_env`, derive `real` with the ceiling removed for that one read.
- Decide what an empty `real` means. Either it refuses ("fence: <here> is in no repository; refusing"), with the jailed waiver c0114 uses for the hooks, or the design records why an empty `real` is safe. First grep the specs for fences entered outside a repository: `fence-cache-entry`, c0059 `adapt`, c0075 `wiring`, c0114 `guards`.
- Do the same in `tests/lib/fence.luau`'s `git()`: run it with `-u GIT_CEILING_DIRECTORIES`, and only for these reads, never in the specs' environment.
- Add a case to an unsequestered guard spec (`tests/tooling/repo-fence.spec.luau`, or a new tooling spec). A fence entered from `pickman/` with `GIT_CEILING_DIRECTORIES=<fixture root>` inherited must record the fixture's common dir and refuse `git update-ref` there. Give it its `ALLOWED` entry, and a Rules row whose mutant is the read with the ceiling kept.
- Then update the testing skill's guarantee to name the ceiling.
Lesson: testing/derive-after-stripping-overrides

### F2 [medium] The new `GIT_DIR` cases don't kill the fix review-001 named as the tempting one: strip only `GIT_DIR` before the read
Where: `z-nile/.tracker/issues/c0120/acceptance/homes.spec.luau`, the two `escapeProbe` cases; Rules row W7.
Evidence: `fence-mut.sh` moves only `unset GIT_DIR` above `real=` and leaves the full strip below it. Both cases' scenarios pass against it (`GIT_DIR=.git` from `pickman/`: the clone's `.git`, REFUSED; foreign `GIT_DIR` from the root: the clone, REFUSED). With `GIT_COMMON_DIR=<foreign>/.git` inherited, the same mutant records the foreign repository and ESCAPED. The shipped code is correct: with it, REFUSED.
Critique: the strip lists ten overrides and the cases seed one. The lesson the author added (testing/derive-after-stripping-overrides) names `GIT_WORK_TREE`, `GIT_COMMON_DIR` and `GIT_CONFIG_PARAMETERS`, but only `GIT_DIR` is pinned. Since homes.spec is sequestered, the tempting fix is to leave it.
Consequences: a case per override is ten fixtures. The ones that can redirect or break the read are `GIT_DIR`, `GIT_COMMON_DIR`, `GIT_WORK_TREE` (with `GIT_DIR`) and `GIT_CONFIG_PARAMETERS` (for example `core.worktree` or `safe.directory`), plus the ceiling from F1.
Recommendation: in the same unsequestered spec as F1's case, add one fence call from `pickman/` with `GIT_COMMON_DIR` at a foreign fixture repository inherited. Assert the recorded repository and the refused `update-ref`, as the existing cases do. Add a mutant row "only `GIT_DIR` stripped before the read" and run it. That spec isn't sequestered, so the build branch may add it. If the author prefers homes.spec, the change belongs on prep, as with 98b5154.
Lesson: testing/seed-every-enumerated-case

## The two pre-existing reads refute-001 left unchanged
- **The first line of every `check.sh`** (`git -C "$HERE" rev-parse --show-toplevel`) is not a path to the real repository.
  - With a relative `GIT_DIR`, or a foreign one without `core.worktree`, git reports `$HERE` itself or nothing. `source …/z-nile/lib/ac.sh` then fails, and the check.sh stops.
  - With a foreign repository whose `core.worktree` is another checkout, that checkout's `ac.sh` fences that checkout. Its `_ac_rel` is then an absolute path containing `/.tracker/`, so it refuses ("under no project root"), and nothing runs against either repository.
  - An inherited root ceiling makes the read fail too. It fails closed.
- **`pickman_guarded`** is not a path either. It reads with the caller's environment, which is the environment the publisher's own git uses, so the answer is about the repository the publisher would change. A failed read returns 1, which the caller treats as guarded. Its one weak answer (`unguarded` for the real root) comes from F1's empty `PICKMAN_FENCE_REAL_GIT`, and F1's fix covers it.
- Other inherited variables checked:
  - `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_COMMON_DIR` and `GIT_CONFIG_*` are stripped before the read; `GIT_COMMON_DIR` was probed (REFUSED).
  - `HOME`, `XDG_CONFIG_HOME`, `GIT_CONFIG_GLOBAL` and `GIT_CONFIG_SYSTEM` only choose configuration files. The fence's keys are `GIT_CONFIG_COUNT` entries, which take precedence over every file, so these can't remove `core.hooksPath`.
  - An inherited `PICKMAN_FENCE_HOOKS` naming a folder of permissive hooks is honoured by design ("the first guard's hook stays in force"). That is c0114's rule, unchanged here. It is not a finding of this round, but it is worth a capture if the lead agrees.

## Judged criteria (code mode only)
- JC1: pass. `git show -M --name-status 1fec94f` is still 632 entries, all R100. The edits commits have no renames: 6d35644 (9 A, 69 M), 2350b12 (2 M: `fence.sh`, repo-fence's `ALLOWED` line), 9e91723 (refute A, c0120.md M). Against origin/prep-c0120, `git diff -M100% --name-status … | grep -v '^R100'` lists 102 paths. These are review-001's 101 plus `refute-001.md`, each named in the design. The prep files came in by merge and are on prep's side of the base. The redo list now regenerates the moves commit on the new base and keeps conflicts in the edits (review-001 F2), which protects JC1 after the restack.

## The three expected reds
- AC11: the one failure is still `z-nile/.tracker/issues/c0114/check.sh: z-nile/next (from .)`, c0114 being unfinished, as claimed.
- AC16: R0034 is active (`./zn busy tracker src tests` prints `raft R0034 is active`), and other branches and worktrees change the old paths. This is the freeze, as claimed.
- AC17: `R0012 is at pickman/.tracker/rafts/R0012, not done`, as claimed.

## Candidate lesson (for the lead)
- testing: a guard that derives what it protects from a git discovery read must not fail open when that read finds nothing. An override can make the read fail as well as redirect it, and `GIT_CEILING_DIRECTORIES` can't simply be stripped, because the fence accumulates it. This is c0120 code review 002 F1, after review 001 F1. Check: for each value a guard reads from git, what does the guard do when the read returns nothing? Is there a case with an inherited ceiling at the checkout's root, entered from a project home?

Verdict: changes

# Refute 001: c0120 (code review 001)

- F1: fixed (`2350b12`). In `pickman_fence_env`, the full `unset` of the repository overrides (`GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_COMMON_DIR`, `GIT_OBJECT_DIRECTORY`, `GIT_ALTERNATE_OBJECT_DIRECTORIES`, `GIT_NAMESPACE`, `GIT_PREFIX`, `GIT_CONFIG_PARAMETERS`, `GIT_CONFIG_COUNT`) now comes after the hooks refusal and before `real=`. `real` is the one value the fence derives from git. W2's rule holds, because nothing after the refusal returns early (W2 still killed).
  - The cases are sequestered, so they were made in prep (`98b5154`, merged here as `9fad9b7`). `homes.spec` has a fence entered from `pickman/` with `GIT_DIR=.git` inherited, and one entered from the root with `GIT_DIR` at another fixture repository. Each checks that `PICKMAN_FENCE_REAL_GIT` names the checkout's common dir and that `git update-ref` there is refused.
  - On the first build's order both fail (the update succeeds); fixed, `homes.spec` is 16/16. Rules row W7 ("`real` read before the unset"): run, killed by both. W1 to W6 rerun in this branch: killed.
  - repo-fence's `ALLOWED` entry for the promoted `homes.spec` covers `GIT_DIR`. The promotion dry run passes.
  - The audit for other git calls made before the strip:
    - `pickman_fence_ceiling`, `_refusals`, `_sentinel` and `pickman_home_fence` make none.
    - `ac.sh` makes none before the root fence.
    - The runner's Luau side (`tests/lib/fence.luau`) runs every git call through `env -u` of the same overrides.
    - Two pre-existing reads remain, outside this change. Every `check.sh`'s first line, `git -C "$HERE" rev-parse --show-toplevel`, is sequestered and runs before `ac.sh`; with a foreign `GIT_DIR` it fails, or sources another checkout's `ac.sh`, which fences that checkout. `pickman_guarded` reads the repository with the caller's environment, which is the one the caller's git acts on.
  - The prototype got the same fix by an amend: `proto-c0120`'s edits commit is now `c9c6070` (local only; the c0115 prototype stacks on it).
  - Lesson testing/derive-after-stripping-overrides (new).
- F2: fixed. The Verification log's redo list is rewritten as recommended:
  1. check Phase 1, with c0114, R0034 and R0012 done;
  2. regenerate the renames-only commit on a fresh branch from the new `origin/main` with §1's table and loop, which covers folders promoted since;
  3. cherry-pick the edits and resolve conflicts only there;
  4. apply the c0114 overrides, plus a named override for any newly promoted pickman spec that turns red;
  5. run Implementation steps 11 and 12;
  6. expect 17/17, or 16/17 with only AC16 red.
  - The c0114 override diff is committed on prep as `z-nile/.tracker/issues/c0120/c0114-overrides.patch`. Lesson: a note on ticket-prep/instructions-runnable-where-they-run.
- F3: fixed. The log and #100 say R0034, as `./zn busy tracker src tests` prints. Lesson: a note on ticket-prep/restated-rules-move-together.
- Results: the full gate passes (pickman 1068/157, z-nile 829/119). c0120's `check.sh` is 14/17, with the same three reds for the same reasons. Sequestration: 103 item-root `check.sh` and `acceptance/` files, all R100 against `prep-c0120`. `./zn lessons --check` and `--uncovered c0120` pass.

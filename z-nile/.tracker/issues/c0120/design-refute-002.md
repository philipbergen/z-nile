# Refute 002: c0120 (design review 002)

- F1: fixed, as a redesign along the review's split, not a save-and-restore. `pickman_fence` in `z-nile/lib/fence.sh` is now four steps, each a function, run in this order (§3 step 5):
  1. `pickman_fence_ceiling`: adds `<dir>/.cache` to `GIT_CEILING_DIRECTORIES` once. It touches nothing else, cannot fail, and runs first.
  2. `pickman_fence_refusals`: reads only. A `.cache` that is a symlink or a file, or a folder sentinel, refuses, in every mode. Nothing waives it.
  3. `pickman_fence_env`: its one refusal (no ref-guard hooks, c0114's `jailed` waiver unchanged) is a read made before any change. From its first change on it never returns early: it unsets the inherited overrides and sets the whole set again, `GIT_CONFIG_COUNT` included.
  4. `pickman_fence_sentinel`: the writes, last.
  - `pickman_fence` refuses on any step, as before. The new `pickman_home_fence` is what `ac.sh` calls for a home (`|| exit 1`, stderr shown). It waives only a failed sentinel write, and only when all three of the runner's jail markers are set (`PICKMAN_TEST_JAIL=sandbox-exec`, `PICKMAN_FENCE_SPECS=1`, `PICKMAN_TEST_FENCE`). It says so on stderr. Every other failure refuses. `ac.sh` no longer names a guard variable, so its repo-fence `ALLOWED` entry is gone. `cachepaths` lists the new lines. The testing skill's Fence bullet says exactly when the sentinel is skipped.
  - `homes.spec`, the review's three cases:
    - a symlinked `pickman/.cache` with the spec guards on refuses with no jail marker, refuses inside the jail, and writes nothing through the link;
    - under the jail markers, with `pickman/.cache` at `chmod 555` and no sentinel, the check.sh runs. The ceiling names `pickman/.cache`, `GIT_CONFIG_COUNT` equals what a z-nile check.sh sees, and the ref guard refuses `git update-ref` in the fixture. The same run with no jail marker refuses;
    - the statement order is pinned: a home fence refused for want of hooks leaves `GIT_CONFIG_COUNT` and `GIT_CONFIG_KEY_0` as they were.
  - repo-fence gains the `ALLOWED` entry for the promoted `tests/acceptance/c0120/homes.spec.luau`. The promotion dry run (E7) passes.
  - Mutants, all run and killed:
    - W1, a waiver for any failure in a spec run;
    - W1b, a sentinel waiver keyed on `PICKMAN_FENCE_SPECS` alone;
    - W2, `GIT_CONFIG_COUNT` unset before the environment step's refusal;
    - W3, `GIT_CONFIG_COUNT` left unset after the waiver;
    - W4, the ceiling exported only after the writes;
    - W5, the refusals waived under the jail marker alone.
    - Round 1's M56 and M57, rerun against the new code.
  - The audit of every other guard function the fence or runner calls, for a waiver keyed on failure or an early return that weakens inherited guards:
    - the runner's `pickman_fence "$1" specs "$2" && … && exec`: fails closed, and the run never starts;
    - the root fence in `ac.sh` (`|| exit 1`): fails closed;
    - c0114's hooks waiver: keyed on the three markers and the checkout's place, not on failure;
    - the jail decision in `fence.luau`: a failed `sandbox-exec` trial leads to probes and an explicit "fixture of a guarded checkout" answer, never to the failure itself;
    - `linkProbe`: "error" refuses;
    - `fence.alive`: reads a refusal as alive;
    - `pickman_guarded`: only "unguarded" is a no;
    - the lock and the sweeper: fail closed.
  - One instance of the pattern was found: `ac.sh` hid the stderr of the `z-nile/roots --projects` lookup it fails closed on. It no longer does.
  - consequences:
    - `pickman_fence`'s writes now come after the environment. `GH_CONFIG_DIR` is exported before `gh-none` is made, which happens in the same call, before anything runs.
    - The edits commit is now `632dba2`.
    - Size is +3,815/−400, about 1,830 lines outside the specs.
- F2: fixed. The design names `632dba2` and marks `proto-c0120` "local only". `prototype.patch` is described as a scratch file handed to the lead and committed nowhere; the design needs neither it nor the branch. §1 now writes down the move loop itself. The Design line says 15/17.
- Lessons: a note in architecture/guard-no-is-explicit ("the same rule for waivers"), with a wider check question. An incident line in ticket-prep/restated-rules-move-together. Both are in harvest.md.

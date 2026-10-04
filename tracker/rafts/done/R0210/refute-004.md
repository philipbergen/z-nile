# Refute 004: R0210

- F1: fixed: the guards never act through a symlinked `.cache`, and never delete recursively.
  - **`fence.sh`:** `pickman_fence` refuses (`… is not a plain folder (a symlink or a file); refusing. Stop and report this.`) when the checkout's `.cache` is a symlink or a file. `ac.sh` now exits on that refusal (`pickman_fence … || exit 1`). A `.cache/.git` folder is refused, not deleted. A `.cache/.git` symlink is unlinked with `rm -f`, never followed. No `rm -rf` is left in `fence.sh`.
  - **Runner:** `fence.enter()` refuses a symlinked or file `.cache` before it writes anything (no lock, no snapshot).
  - **Jail:** it denies writes to the `.cache` entry itself, written and resolved, after allowing its contents. So a spec can't remove, rename or replace `.cache`, and the gate's jail case probes that live (`touch -c -r .cache .cache` must fail).
  - **Spec:** new, not sequestered: `tests/tooling/fence-cache-entry.spec.luau`. Its cases: a symlinked `.cache` is refused and the stand-in `.git` behind it survives; a `.cache/.git` folder is refused and its `commondir` survives; a `.cache/.git` symlink is unlinked and its target survives; and the runner refuses a symlinked `.cache` without touching the stand-in folder at all (its modification time, at nanosecond precision, is unchanged).
  - **Mutants:** M13 (the old `rm -rf` sentinel), M14 (`fence.sh` accepts a symlinked `.cache`), M15 (the runner accepts it) and J13 (the `.cache` entry writable in the jail) are each killed. M15 was killed only once the case required the stand-in to stay untouched.
- F2: fixed: the jail no longer allows the per-user temp folder.
  - **The run's own temp folder:** each top-level run makes a fresh `pickman-run.XXXXXX` under the shell's temp folder, outside the checkout, so a spec's `mktemp -d` still lands outside `.cache`, as c0660's spec requires. Specs get it as `TMPDIR`; on macOS a `mktemp` stub first on the run's `PATH` puts template-less `mktemp` there too. It is removed when the run ends, or refuses.
  - **What the jail allows:** only the run's own temp folder (written and resolved), this checkout's `.cache` contents and `/dev`.
  - **Proven:** the gate's jail case requires that the user temp folder (`getconf DARWIN_USER_TEMP_DIR`) and `/private/tmp` can't be written, that `TMPDIR` lies outside the checkout, and that a plain `mktemp -d` lands inside `TMPDIR`. The outer-sandbox probes (`escapes`) also require the user temp folder to be closed. J14 (the user temp folder allowed again) is killed. c0660's helper spec and `migrate-odd`, both of which call `mktemp -d`, pass.
  - **Docs:** the testing skill's Jail bullet now describes this, and that `fence.sh` never deletes recursively.

The raft check passes 7/7 with all of this, the full gate included. Two high findings were fixed, so another review round follows.

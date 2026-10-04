# Refute 006: R0210

The high finding blocked the merge again. The user chose to fix it at the writers, then land.

- F1: fixed at the writers, as the user chose. Whatever the jail misses, a symlink at the top of `.cache` is never written through.
  - **Writers:** every unjailed writer there now writes a fresh file outside and renames it into place with `mv -f`, which replaces a link instead of following it.
    - `sh.writeReplacing` (new, `scripts/lib/sh.luau`) writes the tracker's focus file, claim file and board.
    - `scripts/check.sh` builds rojo's `check.rbxl` in a fresh `mktemp -d` and downloads `globalTypes.d.luau` to a `mktemp` file, then renames each in. The download also re-runs when the path is a link.
    - `scripts/deploy-beta.luau` builds its place outside the checkout.
    - `fence.sh` writes its sentinel through an exclusively created `mktemp` file in `.cache`, then renames it.
  - **Runner:** it unlinks top-level `.cache` symlinks right after the specs' group is reaped, as well as before a run.
  - **Outer sandbox:** one that claims to protect the repository must also refuse `ln -s` at the top of `.cache`, or the run refuses.
  - **Proven:** `fence-cache-entry.spec` gains "a tracker write replaces a symlink at its path instead of writing through it" (W1, writing straight to the path, is killed). Raft check 7/7.
- F2: fixed: the launcher's child forks a watchdog inside the specs' process group, with its stdio closed. When the launcher is gone, the watchdog kills the whole group.
  - **Verified** (by accident, the scenario itself): a `SIGKILL` to the whole run's process group, launcher included, stopped the sleeping spec within seconds. The lock left behind recorded only dead processes, and the next run took it over and released it.
  - **Unchanged:** Ctrl-C, TERM and HUP are still forwarded.
- F3: fixed: the escape pattern in `profile` no longer escapes `{`, `}` and `|` with `%`, so luau-lsp's warning is gone. The rule still works: the gate's live probe (`ln -s` at the top of `.cache` must fail) passes.

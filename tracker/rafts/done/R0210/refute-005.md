# Refute 005: R0210

- F1: fixed: the jail forbids creating a symlink at the top level of `.cache`, whether made there or renamed there from deeper: `(deny file-write-create (require-all (vnode-type SYMLINK) (regex #"^<cache>/[^/]+$")))`, for the path as written and resolved.
  - **Experiment** in `$TMPDIR`: a top-level link and a rename of a deeper link up were both refused, while a deeper link and a plain top-level file worked. c0530's setup spec, which builds stub tools from symlinks, passes.
  - **Leftover links:** a top-level run unlinks (`rm -f`, never followed) any symlink at the top of `.cache` left from before.
  - **Proven every run:** the gate's jail case requires `ln -s /nonexistent .cache/<probe>` to fail. J15 (no symlink rule) is killed.
  - **Why the writers are unchanged:** with no way to plant a link where they write, the unjailed writers (rojo `-o`, focus, claim, board) no longer need rename-replace.
- F2: handled as the user chose (reap, plus a review-only note).
  - **Reaping:** the runner starts the specs through a small Perl launcher. The launcher forks the run into a process group of its own and stays in the terminal's group, passing on INT, TERM and HUP, so Ctrl-C still works. When the run ends it kills what is left in that group, before the second snapshot.
  - **Proven:** `tests/tooling/fence-leftovers.spec.luau` runs a copied runner in a fixture whose probe leaves a background process, which must be dead when the nested run ends. R1 (no group kill) is killed.
  - **Checked by hand** at top level: the background process was stopped, a `setsid` one survived as designed, and exit codes still pass through (`--jobs x` exits 2).
  - **Review-only:** a process that leaves the group on purpose (`setsid`, a double fork into a new session) is now listed under the testing skill's "Caught only by review", with why it matters (it stays jailed, but outlives the run and could change a `.cache` copy that an unjailed `check.sh` later runs).
  - **Dropped approach:** reaping by an inherited token was tried first and dropped: current macOS doesn't show another process's environment to `ps -E`, even unsandboxed.
- F3: fixed: the stub takes `-t prefix` and makes `$TMPDIR/<prefix>.XXXXXXXXXX`. The gate's jail case requires `mktemp -t pickman` to land in `TMPDIR`.

The raft check passes 7/7 with all of this, the full gate included. As the user decided, one more review round follows, then the raft lands if it finds no new high.

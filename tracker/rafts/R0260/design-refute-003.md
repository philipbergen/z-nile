# Design refute 003: R0260
All three findings are against c0810, which the user removed from R0260 after this round (2026-10-04, "Drop c0810 from R0260"). Each is recorded in c0810's "Prep history" for its redesign; none applies to the six issues that remain, which had no findings this round.

- F1: refuted: out of this raft's scope. c0810 was removed from R0260 by the user's decision; the three routes (a `commondir` file, `config.worktree`, `[core] worktree =` on the section line) are listed in c0810 for the redesign, which points at a real Linux jail. consequences: c0840's skill text no longer mentions a git shim, and its AC4 no longer requires it. The Linux gap stays under "Caught only by review", as today.
- F2: refuted: out of this raft's scope, for the same reason; the cases missing for `GIT_COMMON_DIR`, `GIT_INDEX_FILE`, `GIT_OBJECT_DIRECTORY` and `worktree move`, and the `--template` over-refusal, are recorded in c0810. consequences: none for R0260.
- F3: refuted: out of this raft's scope; the commands git itself starts are recorded in c0810. consequences: none for R0260.

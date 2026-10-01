# Refute 003: R0140

- F1: fixed: a new case in `setup-skip-gate.spec.luau` requires `set -euo pipefail` to be the only `set` line in `setup.sh` and forbids a `trap` statement (a `^%s*trap%s` match, because the word "Bootstrap" in the header comment contains "trap "). Prototype mutants `set +e` before the stage and `trap true ERR` both fail on it. consequences: `setup.sh` can't change shell options or add a trap without a chore, the accepted route.
- F2: fixed: the documented command is `rm -rf .cache/board-ci && gh run download -n tracker-board -D .cache/board-ci`, pinned in `board-docs.spec` (the `rm -rf` mutant fails) and used by OC1. consequences: none.
- F3: fixed: the make-prompt case now requires the phrase `isn't a member` (the exclusion of the raft's own issues); the mutant that drops it fails. consequences: none.
- F4: fixed: review item 4 now says `ALL` carries no list (grep alone, also with the basename); the token is pinned in the review case, and the mutant that removes it fails.
- F5: fixed: c0460's Affected specs lists `tests/acceptance/c0050/clone.spec.luau` for `SETUP.md` (run green on the prototype together with `c0330`, `c0410` and `c0010`); the raft document says E1–E6.
- F6: fixed: the chore route says to prefer narrowing, and if the spec must go, the chore also drops the line naming it from the owning item's `check.sh` (token `prefer narrowing` pinned, mutant fails). consequences: a chore may edit a done item's `check.sh`; that is not sequestered work, since the done item's own execution is over.

Round 3 is the last allowed round. All findings were mechanical and are fixed; no further review round was run.

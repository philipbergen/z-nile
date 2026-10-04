# Refute 007: R0250 design review 007

- F1: fixed: land carries only `M` of a backlog `<ID>.md` that is `design: draft` on **both** sides, with the `status:` line unchanged. New refusal sub-cases cover a capture setting its own design to ready and one changing its status line.
- F2: fixed: an `A` is refused outright. Issues are created by `tracker.sh new issue`, which publishes the stub and `check.sh`, so a locally added issue (offline, or one reusing an id) never lands this way, and any `check.sh` change is refused. A sub-case adds an issue locally and expects the refusal. AC2, the case name and the Rules row now state the narrower rule. consequences: an offline-created issue needs a PR, which is acceptable: offline creation is the exception.
- F3: fixed: an item whose first appearance is already in `done/` gets a close day and no spell.
- F4: fixed:
  - the quarter window clamps like the month view (2026-05-31 goes back to 2026-02-28, then to the Monday before);
  - "today" falls back to the data when the history has no item commits;
  - `periods` is optional (nil without a today): board-stats asserts nil for the undated tree, and stats.spec unwraps it with `assert`.

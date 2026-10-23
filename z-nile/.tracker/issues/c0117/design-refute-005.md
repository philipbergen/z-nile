# Refute 005: c0117 (answers to design-review-005.md)
The user decided on 2026-10-23: "Fix, no more review". Each finding below is fixed as the reviewer recommended, and the design is `design: ready`. The code review checks them. The prototype is `proto-c0117` on `proto-c0116` 5fa0a8d: the simulation b57df84, then one edits commit. Experiments and mutants ran only in clones under the session scratchpad.

- F1: fixed.
  - **Refs of each run's own.** Each dispatcher process fetches into `refs/zn-dispatch/run-<id>/<name>` (`main`, `broker`, `models`, `pr-<n>`). `<id>` is a uuid, and a lock file in the git common dir, held for the process's life, says the run is alive. The wrapper fetches into `refs/zn-wrap/<id>/main` and deletes it afterwards.
  - **Shas, not refs.** `freshMain` returns the sha, and the run keeps it. The tripwire's "HEAD moved only forward" check, the gates' merge base and the registry reads all use that sha.
  - **Retries.** Fetches retry three times with back-off, as `publish.commit` does. A fetch that still fails stops the run as a tripwire whose detail names the network, and `retry` clears it.
  - **Cleanup.** A run deletes its own refs at its end (`dispatcher.main` always does). Every run's start and `vet` sweep the refs of runs whose lock nobody holds.
  - **Cases (control-cli).**
    - Two runs at once each publish five tracker commits through their brokers, with a lock held on the old shared ref throughout. Both exit 0, all ten publishes land, and no `refs/zn-dispatch/` ref is left.
    - A fetch fails twice on a lock, then works, and the run exits 0.
    - A lost run's leftover ref is gone after the next run.
  - **Mutants.** M138 (one shared ref again), M139 (no retry), M140 (no sweep) and M141 (refs left behind).
  - **Consequences.** One lock helper process per dispatcher process. G18 names the per-run refs.
- F2: fixed. `STEP_ENV["claude-cli"]` raises only `BASH_MAX_TIMEOUT_MS`, to two hours. The default stays at 120 s. The headless section (word for word in all four skills, pinned by docs.spec) tells the author to give its one review command a two-hour timeout. G22 names the cost of each choice. E15 settles whether claude honours the timeout in `-p` mode. The control-cli case keeps its `bashmax` check.
- F3: fixed. A nested runner beats once a second for as long as its loop runs, which is only while it is alive and within its own limits. A beat now means "alive and within my limits".
  - **New case.** The author's limit is `stall_seconds = 6`, and the reviewer is silent for 12 s inside one tool, within its `tool_seconds = 16`. The author ends `ok`.
  - **Mutant.** M142 (a beat only while the CLI prints).
  - **The quiet-reviewer case.** The reviewer stalls at its own limit, and its beats stop. The assertion is now on the reviewer's own state (`stalled`), since its author goes on once the review command returns.
- Lesson: the note goes on `waiting-steps-show-liveness`, as the reviewer suggested.

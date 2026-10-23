# Refute 008: R0021

- F1: fixed, and run.
  - **New case:** `adapt :: a check run's status move publishes nothing either, and says so`. It finds the issue the previous case published (`probe-two`) and runs `status <id> preparing` under the guards. It asserts the output says `not publishing`, and that neither origin's tip nor HEAD moves.
  - **Wiring:** the case is in AC2's `cases_pass` list, and AC2's text names the status move.
  - **Mutant:** P5 (the refusal applies only when the command is `new`) is killed by the new case on `proto3-r0210`. The case passes with the real implementation: 7/7.
  - `new raft` and `start`'s claim go through the same `publishing()`, which is noted in the P5 row.
  - **Consequences:** none. `status` under the guard fails or succeeds exactly as it does with `PICKMAN_PUBLISH=0`, and the case asserts only that nothing is published and that the output says why.
- F2: fixed. R0021's Phase 1 no longer says to merge a prototype branch.
  - The guard files are taken by path from `proto2-c0058`.
  - c0059's implementation ships in the prep as `tracker/issues/c0059/experiments/c0059.patch`, applied with `git apply -3`.
  - The prototypes' `tracker/` files are never taken.
  - The prototype branches are local to the prep machine and are kept until R0021 lands; the patch and the documents suffice without them.
- F3: fixed.
  - The stale "publisher's entry" and `publish.luau` wording is gone from R0021.md (diagram and Order) and from c0058's allowlist paragraph.
  - The Risks section says that E30 passed on the combined prototype and that Phase 1 re-runs it on the landed code.
  - c0059's Rules row now uses the spec's case name.
  - c0060's AC5 again fails on "in new and edited specs", and also requires `c0053` to be named.

This is the third and last review round of this prep. Its one high finding is fixed and mutation-tested, and no open question remains for the user.

# Trace: R0133

Commit: 88d8cd9199e5ccb106e1f8af14426c89ce0d39aa

## Claims

| claim | design | test | code |
|---|---|---|---|
| c0304:P1: two c0045/workstreams cases are stale since #296: worktree --from bases on R0010-demo, a branch a raft worktree no longer makes, and the stream-review case's done now refuses at the published-tip check before it reads reviews |  |  |  |
| c0304:AC1: every case of `c0045/workstreams` passes, the two narrowed ones included, and `c0060/retrofit` still finds no raw git in it. |  |  |  |
| c0304:AC2: `c0045/workstreams` is its merge base (with origin's main, read with `git ls-remote`) with exactly the three reviewed c0304 hunks, byte for byte (the `raft-tip` branch and both `--from` lines in case 1, the push in case 2), and a base that is not the stale form is refused. |  |  |  |
| c0304:AC3: None. That no file other than `z-nile/tests/acceptance/c0045/workstreams.spec.luau` changes outside the tracker (Non-goals) is the code reviewer's to confirm from the layer's diff. |  |  |  |
| c0304:AC4: None. |  |  |  |
| c0374:P1: c0120's slow-tier tests/acceptance/c0120/finished.spec.luau has the same misreadings as check-paths.spec.luau (c0371) |  |  |  |
| c0374:AC1: the finished-check scan passes on the repository, reads a bare `./zn` inside single quotes as text (a helper's argument, a multi-line `bash -c` script), and still reports an unquoted path, a folder path in single quotes and unbalanced quotes, while a path missing before the move stays allowed. |  |  |  |
| c0374:AC2: `c0120/finished.spec` is its merge base (with origin's main, read with `git ls-remote`) with exactly the two reviewed c0374 hunks, byte for byte (the `singleQuoted` helper and the last case's loop), and a base that is not the stale form is refused. |  |  |  |
| c0374:AC3: None. That no file other than `z-nile/tests/acceptance/c0120/finished.spec.luau` changes outside the tracker (Non-goals) is the code reviewer's to confirm from the layer's diff. |  |  |  |
| c0374:AC4: None. |  |  |  |
| c0411:P1: With the `./zn metrics` crash (d0406) fixed, the case 'lists every raft once, sorted by id' in `z-nile/tests/acceptance/c0043/rounds.spec.luau` fails with 'expected deep-equal values', because it builds its expected rafts from a hand-written list of two roots (`pickman/.tracker`, `z-nile/.tracker`) while `./zn metrics` lists the rafts of all seven projects registered in `z-nile/projects.toml`. |  |  |  |
| c0411:P2: `z-nile/tests/acceptance/c0116/retired.spec.luau`, which runs `rounds.spec` in a clone, is red on main today because of the d0406 crash alone, and with d0406 fixed it stays red because of the hand-written list of two roots. |  |  |  |
| c0411:S1: The case builds its expected list from every registered project's root (`rafts`, `rafts/active`, `rafts/done`, `rafts/retired`), so with d0406 fixed it passes on main and keeps passing when a project root or a raft is added. |  |  |  |
| c0411:S2: The case still fails when metrics leaves a raft out, lists one twice or lists them out of order. |  |  |  |
| c0411:S3: With d0406 fixed and this change in place, `z-nile/tests/acceptance/c0116/retired.spec.luau` passes without being edited. |  |  |  |
| c0411:AC1: `c0043/rounds.spec` is its merge base (with origin's main, read with `git ls-remote`) with exactly the two reviewed c0411 hunks, byte for byte, and a base that is not the stale form is refused. |  |  |  |
| c0411:AC2: `c0116/retired.spec` is unedited against its merge base with origin's main. |  |  |  |
| c0411:AC3: None. That no file other than `z-nile/tests/acceptance/c0043/rounds.spec.luau` changes outside the tracker (Non-goals) is the code reviewer's to confirm from the layer's diff. |  |  |  |
| c0411:AC4: None. |  |  |  |
| c0414:P1: R0131 landed d0297 on 2026-11-17 (99c7caad6) while R0133 was in review. Line 23 of `z-nile/.tracker/issues/done/d0297/check.sh` is a failure message, `echo "z-nile/affected.luau has no usage line for --own-acceptance"`, and `z-nile/tests/acceptance/c0120/finished.spec.luau` reads `z-nile/affected.luau` there as a path from the item's home (`z-nile/`), where it does not resolve: `z-nile/.tracker/issues/done/d0297/check.sh: z-nile/affected.luau (from z-nile)`. |  |  |  |
| c0414:P2: That makes `c0120/finished` red on main's slow tier again, and it stops R0133: c0374's AC1 ("passes on the repository as it is") fails as soon as its layer is restacked on that main. It cannot be postponed (zz-rules, Emergent issues). |  |  |  |
| c0414:P3: The spec is right by its own rule and by c0374's (the word holds a `/`, so it is read whatever quotes it is in); the message is the mistake (lesson `zz-test/sentences-in-checks-are-grep-patterns`). |  |  |  |
| c0414:S1: The failure message on line 23 names the file as `affected.luau`, which resolves from the home, so `c0120/finished` reports nothing for d0297 and d0297's `check.sh` still passes. |  |  |  |
| c0414:AC1: c0120's finished rule reports no path in d0297's `check.sh`. |  |  |  |
| c0414:AC2: d0297's `check.sh` passes. |  |  |  |
| c0414:AC3: none |  |  |  |
| c0414:AC4: none |  |  |  |

## Source files

| file | claims |
|---|---|

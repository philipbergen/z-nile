# Refute 002: c0166

- F1: fixed: `Tree.areas` is set by `lessons.load`. `relevant` and `select` take the table as an argument and do not read the file. A nil table makes the core arm and the tag arm miss. relevance.spec builds its table with `lessonareas.parse`, and `two tables disagree` is the case that kills a hard-coded table. Consequences: the CLI fixtures seed their own `lesson-areas.md`, because `engine.copy` would otherwise hand them the live file.

- F2: fixed: the prompt's dropped lesson is `zz-stats/tally`, and mode code keeps `zz-test/wire`. `introducing commit` and the unparseable lesson each have their own fixture, and `./zn commit` refuses `zz-test/bad does not parse`. A matching note with a missing id leaves the loop unsatisfied even when another note is valid, and the pure case passes the valid note first. The plain-commit case stays, and it matches `staleSource` rather than the inverted sentence. Consequences: none beyond those cases. They stay `reasoned` until the prototype of this text runs.

- F3: fixed: `staleSource` is the one function `--uncovered`, `--stale` and `./zn commit` use. A source is stale when it is not on the merge base, it was added after the commit that last changed `check:`, and it is not the first source. `since check` is that count without the base test. A second source on the branch is stale even when the base count is 0. The sentence that said the check must differ is gone. Consequences: the old `needsRewrite(beforeCount > 0, …)` row is `reasoned` again, because the command no longer uses that shape.

- F4: fixed: the merge case fetches, asserts the harvest line arrived, and asserts the merge commit has two parents. The mutant is `HEAD^1`. Consequences: none.

- F5: fixed: no `origin` remote skips the stale check and warns, and `./zn commit` succeeds. `origin` without a resolvable `origin/main` fails closed on `--stale` and on `./zn commit`. `--diff` keeps its own warning and is not that failure. c0084 has no remote, so the skip applies and Overrides stays none. The prototype still has to run c0084. Consequences: a checkout with no remote does not run the stale check.

- F6: fixed: the exact rows live in `acceptance/named-areas.luau`, which is not a `*.spec.luau`. `done` moves the acceptance folder, so the file is at `$A` afterwards, and the gate's collector does not run it. It is not a Touched module. `check.sh` runs `$A/named-areas.luau`. Consequences: `./zn check c0166` still runs it after `done`. `z-nile/check.sh` does not collect it, so a later area change does not turn the gate red.

- F7: fixed: the promoted real-tree case requires a non-empty core whose tags have keys, not the four names. relevance builds its own table. The CLI fixtures seed `lesson-areas.md`. The exact rows stay in `named-areas.luau`. Consequences: none beyond F1's argument.

- F8: fixed: `skill <name>:` rows keep that skill when a query path overlaps a prefix. `zz-arch` is not kept for a maze path. `pickman-arch` is `pickman/src` and `pickman-test` is `pickman/tests`. Raft mode also exercises `z-design`, because the raft recount was 11 of 17 without it and 17 of 17 with it, and a maze raft review then keeps 92 of 130. Recount: design 142 of 142, code 2 of 2 (too few to be the bar). A maze design review keeps 99 of 130. c0166's design query keeps 124 of 124. Consequences: a tooling path keeps zz-arch lessons that a maze path does not. The relevance case is `an engine path keeps a zz-arch lesson a maze path drops`.

- F9: fixed: a repeated core line, mode line, tag or skill is a parse problem and nothing from that line is kept. `core` and `mode` are reserved lesson tags. A line `mode: …` is `mode is reserved`. A missing or unparseable file makes `--for` and `--paths` exit 1 and `--check` report it, and `buildLessons` applies no filter and warns. Consequences: a harvest that adds a prefix edits the existing line. The zz-rules sentence already says a harvest may edit the file.

- F10: fixed: a source or a fifth review file is in force only when the commit that added it contains `lesson-areas.md`. The items counted on 2026-10-27 are named under Existing work and are not edited. When `origin/main` has no such file, nothing is grandfathered, so the fixtures that seed the file still exercise the rule. Consequences: metrics may still print `missing` for a grandfathered loop. `--rounds` and `--stale` do not fail it.

- F11: fixed: the missing cases are in the specs and the Rules table. `--for` keeps an acceptance lesson through the item folder and `--paths` does not. Mode design drops a design-phase zz-arch lesson on a pickman path. A bad mode, a second mode, `--stale --for` and `--stale --when build` exit 2. A raft-document bullet satisfies a member only when `<file>` names that member. Consequences: none.

- F12: fixed: the appended questions that named this issue's artifacts are the general rule. A question that restates one finding is the defect `restated-rules-move-together` now asks about. Consequences: none for the specs.

- F13: fixed: the two locals named `doc` in rounds.spec are renamed `body`, so they do not shadow the helper. Consequences: none. The type error in `pickman/tests/acceptance/f0061/lobby-tooling.spec.luau` line 55 is not this issue's file and is not fixed here.

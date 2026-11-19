---
title: Dry-run a sequestered spec at its promoted place under the guard scan
when: both
tags: [guards, promotion, repo-fence]
check: After the last edit to a sequestered spec, script or `check.sh` (a review round's fixes included), does the Design's Unknowns & experiments record a run of `tests/tooling/repo-fence.spec.luau` on the prep tree with every file of `acceptance/` copied to its promoted place and the allow-list entries the plan names, green, and does a reviewer who finds no such record raise it?
---
`./zn check` and `promote-check` run the sequestered specs and type-check them; neither runs the guard scan, which reads promoted specs for names that switch a guard off. A name added to a spec during a review round fails the gate only after `done` promotes it.

**Why:** c0123 design review 003 F1: a round-2 fix pasted a literal fence variable name into `wording.spec`, whose plan said it needed no allow-list entry; the scan would have turned the gate red at promotion.

**How to apply:** after each edit round, copy the specs to the promoted folder of a throwaway clone, add the entries the plan lists, run `repo-fence.spec` (green), then put a guarded name back into a spec without an entry (red), and remove the copies. Prefer building a guarded name from parts in a spec that only quotes it.

**Note** (d0295 design review 001 F1): the scan reads every `check.sh` under every project root the moment it is written, sequestered ones included, not only promoted specs, and the selector picks nothing for a new `check.sh`, so a prep PR's `--affected` stays green and the next `--full` is red. d0295's `check.sh` unset `GIT_CONFIG_*` to strip a dispatched step's environment; naming a banned name, even to unset it, is enough. Ask: was `tests/tooling/repo-fence.spec.luau` run on the prep tree after the last `check.sh` edit?

**Also** (c0287 design review 001 F1): `done` promotes the whole `acceptance/` folder, scripts included, but `./zn promote-check` copies only `.spec.luau` files and never runs repo-fence. c0287's `slow.sh` unset `GH_CONFIG_DIR` (a guard name) and would have turned main's gate red once promoted. Copy every file of `acceptance/` to its promoted place for the dry run, not only the specs.

**Also** (c0386, a note): c0371's design review 004 F1 added the fixture text of an unquoted grep after `env` and its `-i` option to the sequestered `check-paths-homes.spec`; c0371's documents record no guard-scan run, none of its five design reviews or R0112's reviews asked for one, and R0112's "promotion dry run" was `./zn promote-check`, which runs no guard scan. The lesson's question was asked by no one, so `main` turned red at the bind. The check now asks for a recorded run, which a reviewer can see is missing. c0386's own prep ran it and it caught c0386's new spec naming the option in a header comment.

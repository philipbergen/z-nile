---
title: Dry-run a sequestered spec at its promoted place under the guard scan
when: both
tags: [guards, promotion, repo-fence]
check: After every edit to a sequestered spec or a `check.sh`, was `tests/tooling/repo-fence.spec.luau` run on the prep tree (for a spec: copied to `z-nile/tests/acceptance/<id>/` with the allow-list entries the plan names), and does it pass there?
---
`./zn check` and `promote-check` run the sequestered specs and type-check them; neither runs the guard scan, which reads promoted specs for names that switch a guard off. A name added to a spec during a review round fails the gate only after `done` promotes it.

**Why:** c0123 design review 003 F1: a round-2 fix pasted a literal fence variable name into `wording.spec`, whose plan said it needed no allow-list entry; the scan would have turned the gate red at promotion.

**How to apply:** after each edit round, copy the specs to the promoted folder of a throwaway clone, add the entries the plan lists, run `repo-fence.spec` (green), then put a guarded name back into a spec without an entry (red), and remove the copies. Prefer building a guarded name from parts in a spec that only quotes it.

**Note** (d0295 design review 001 F1): the scan reads every `check.sh` under every project root the moment it is written, sequestered ones included, not only promoted specs, and the selector picks nothing for a new `check.sh`, so a prep PR's `--affected` stays green and the next `--full` is red. d0295's `check.sh` unset `GIT_CONFIG_*` to strip a dispatched step's environment; naming a banned name, even to unset it, is enough. Ask: was `tests/tooling/repo-fence.spec.luau` run on the prep tree after the last `check.sh` edit?

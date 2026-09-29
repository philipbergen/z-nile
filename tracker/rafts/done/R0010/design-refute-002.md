# Response to design-review-002

- F1: fixed: the root cause is in the tooling. `graph.build` now strips Luau line and block comments before scanning (`graph.stripComments`, pinned by a new case in tests/tooling/affected.spec.luau). The comment in resolve-require is also reworded. New `tracker.sh promote-check <R>` dry-runs promotion (type check + meta). It's wired in as R0010's RC2, in the raft `check.sh` template, execute-raft Phase 3 and ticket-prep. Run now in prep, it reports only the expected missing module, `@tests/lib/place`.
- F2: fixed: setup.sh appends `$HOME/.rokit/bin` to `$GITHUB_PATH` when set. The acceptance step calls `lune` directly, and `rojo` resolves for `place.load()`.
- F3: fixed: `rokit authenticate github --token "$GH_TOKEN" --skip-parse --skip-verify` (both flags confirmed in rokit 1.2.0's `--help`), with the fallback of dropping the step.
- F4: fixed: the AC2 spec requires a step whose trimmed `run` is exactly `scripts/setup.sh`. `echo … scripts/setup.sh` no longer passes. setup.sh's last stage is `scripts/check.sh --full`, so a green run implies the gate passed.
- F5: fixed: the spend diff also excludes `tests/acceptance/`, so promoted prep specs are no longer counted as execution spend.
- F6: fixed: the lifecycle fixture builds its require text by concatenation (`REQ`).
- F7: fixed: c0010's Implementation step 2 lists all three setup.sh changes, and step 1 names both workflow steps.

# Refute 003 (f0265): round 3 answered

- F1: fixed: every claim publish (issue or raft, takeover included) records the stamp in the checkout that made it; the carried `prepared` is refused only when the checkout remembers a stamp that differs (no memory passes; a checkout's own re-claim updates it, so c0053/commands-prep stays green); the skills say to claim from inside the worktree. New case: the taker's own carried move passes. Overrides stays none; the suite run on the rule is the executor's Phase 1 (step 1), since the edge is not prototyped.
- F2: fixed: `heartbeat.autoAllowed(env, commonDir)` (pure; false when the common dir is in `PICKMAN_FENCE_REAL_GIT`), pure cases and mutant run; a nested `./zn` in a check never beats.
- F3: fixed: a malformed ref makes stale claims unknown everywhere (lost, status, takeover), and its message carries `git push origin :<ref>`; lost.spec follows; AC3's label was already that reading.
- F4: fixed: a takeover case with `questions.md` in the main checkout; the rule is read from `mainRoot()`.
- F5: fixed: `race.spec` forces the race with a one-push `git` shim (publish retries its callback); row: pure run, edge reasoned only for lack of an edge prototype.
- F6: fixed: `race.spec` cases for a failed tick and for a restamp stop (shim-driven), rows added.
- F7: fixed: a background tick during long outer commands (`check`, `done`, `land`, the gate, `dispatch`), case in `race.spec` (a check that polls for a beat dated during its run).
- F8: not mine to decide: reported (Assumptions) with the three options; the c0265 outcomes are covered where they are in this issue's scope (long-command beats; takeover recorded in the claim commit subject) and the rest named.
- F9: fixed: the three sentences rewritten.
- F10: fixed: the old claimant is told once on stderr, its entry deleted, no beat of either stamp (assertions).
- F11: fixed: own process group, killed as a group (the runner's helper).
- F12: fixed: `heartbeat.setting(env, name, default)` pure with cases and mutants run.
- F13: fixed in part: `fold` case and row; `recombine` and `start` stay `reasoned` with the reason (two rafts / a PR needed).

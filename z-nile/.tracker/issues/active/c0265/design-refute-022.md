# Refutations and fixes: design-review-022
- F1: fixed: the constraints on the later layers are stated (a not-a-claim refusal before any memory refusal; no case runs a command in a checkout after its claim was restamped or taken over), the takeover and restamp cases claim in worktrees that run nothing afterwards (edge: wt3; race: wtB), and E16 runs the five files on variants A (told on stdout) and B (commands refused): both green; C stays red by design; consequences: the envelope patch was rebuilt on the round-4 prototype (new hash).
- F2: fixed: a shim marker pins the call site of the landing read (mutant K5).
- F3: fixed: the heartbeat's fetches retry once on `cannot lock ref`; a beat names one `origin/main` sha for its whole attempt; two cases and mutants K1 and K2; Shared state says the namespaces are shared; lesson note on read-paired-facts-at-one-moment.
- F4: fixed: hung push and hung gh cases (mutants K3, K4); the dead `lshang` of lost.spec dropped.
- F5: fixed: the proof's bounds are 30 s deadlines and 60 s limits.
- F6: fixed: counts, base of the envelope, the interface block, the fetch count, `35m` from 2130 s (mutant K6), c0040's own line, the first-parent note moved to history-tests-survive-squash.

# Refute 003: R0003 (design mode)

- F1: fixed: the Tick semantics now fix the order at each time (record, check expectations, then `stopWhen`). New expect.spec cases: an expectation at the stop tick fails as itself (not "never reached"), and `stopWhen` receives times 1..6 and the Ping event that stops the run. The reviewer's `stopfirst` and `stopevents` mutants fail 4 and 1 cases.
- F2: fixed: the design says `record` changes only what is kept. New expect.spec case: `record = false` with a failing expectation fails at its tick, and its replay has empty states. The skip mutant fails.
- F3: fixed: the design says replay re-runs the model. New replay.spec case counts one `new` and nine `step` calls. The `fakereplay` mutant fails 2 cases.
- F4: fixed (the reviewer's first option): the replay records `failure.kind` (`expect` | `never` | `step`). A step-kind replay runs the failing step with its intents and re-raises the error, without writing a new replay. New replay.spec case (the error is triggered by an intent at the failing tick), plus kind assertions in the three failure paths. A mutant that stops before the failing step fails.
- F5: fixed: both optional cases added. A function expectation mutates its argument and the trace is unchanged; an impure `stopWhen` makes the runs differ in length, and the divergence is reported at tick 4. Both mutants fail.

After round 3 (the cap) the prototype passes 49/49; every mutant named in rounds 1–3 fails at least one case; the specs type-check (0 errors), format and lint clean. The remaining decision (proceed without a fourth review round) goes to the user, per ticket-prep step 5.4.

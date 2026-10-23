# Review 001: R0047 (code mode)
Inputs: HEAD f10ad6f9 (origin/main 844687a1 after `scripts/tracker.sh sync --fetch`); `git diff origin/main...HEAD`; R0047.md and check.sh; c0127 (document, check.sh, rules/reuse/skill specs); c0131 (document, check.sh, accept/refuse specs); the testing skill's "Specs never touch the real repository"; review and build lessons.
Runs: `scripts/check.sh --full` GATE PASSED (2037 passed, 0 failed, 298 spec files, 133.1 s). `scripts/tracker.sh check c0131` 2/2 PASS. c0127's specs run directly, not through `tracker.sh check c0127` (AC5 would dispatch a CI run): rules 3/3, reuse 13/13, skill 1/1. Sequestration: only c0131's three added files (`A`), as expected for an emergent issue; c0127's and R0047's sequestered files unchanged.
Mutants (each restored, tree clean): (1) the top's id read from `<lock>/pid` instead of `start-<pid>` (so every live top record looks reused): reuse.spec 13/13 still passes, caught only by c0058 `lock.spec` "two runs waiting on one dead lock take it one at a time" (F2); (2) the hook's empty-transaction allow without the `PICKMAN_FENCE_SPECS` test: caught by c0131 refuse.spec and `repo-fence.spec` "every git this run starts refuses ref updates".
Guard change (c0131) judged safe: an empty transaction changes no ref, it stays refused during spec runs, and the other rules are unchanged. Probed in a scratch repository with a logging hook (git 2.54.0): empty `prepared` transactions come from `fetch`/`fetch --prune`/`remote update`/`pull` with nothing new, `gc` and `maintenance run --task=pack-refs`; `remote remove` of a remote with no tracking refs runs no transaction at all, so the old hook never stopped it either. The only new reach is that a check.sh's `git gc` with nothing to pack no longer aborts at that step, and check.sh files' own commands are review's to catch anyway (testing skill).

### F1 [medium] A waiter now runs perl between claiming the takeover mutex and writing its `pid`, so a slow reader gets its mutex removed as unowned and the waiter crashes
Where: tests/lib/fence.luau:236-241 (`takeOverIfStale`: `fence.startOf(me)` → `owner` → `pid`), and :278-280 (`takeLock`: `recordStart` before `pid`)
Evidence: on main the mutex's `pid` is written right after `mkdir`. Now `fence.startOf(me)` (a perl process) runs first, and another waiter removes a mutex with no `pid` once its age (whole seconds, wall clock) reaches `UNOWNED_SECONDS` = 2. Reproduced in a scratch clone outside every repository: a dead lock, a stand-in perl that sleeps 3 s on the reader's call only, two runs started 0.5 s apart. Run A passed; run B died with a Lua error at fence.luau line 241 (`fs.writeFile(`{mutex}/pid`, me)` into a mutex that had been removed), exit 1. A perl start of a second or two is rare, but the gate does run under load (the verification log reports the gate at twice its usual time with another session on the machine; c0133 was just captured for the sweeper under load). The same reader also runs on every wait step: while a live run holds the lock, every 0.1 s step that gets the mutex spawns perl for the waiter's own id (its id never changes) plus one per live record. That is about 2400 extra perl runs over a 240 s wait, and no spec counts them.
Critique: the tempting fix is to raise `UNOWNED_SECONDS` or wrap the `pid` write in `pcall`. A larger threshold slows the recovery of a mutex that really was abandoned, and a `pcall` hides the case where two waiters hold the takeover at once (the one that lost its mutex goes on and judges and removes under a mutex that is now someone else's).
Consequences: the waiter's own start id is a fixed fact about its own process. Reading it once, before `takeLock`'s loop, makes the owner and `start-<me>` writes as immediate as main's `pid` write, and the wait loop's own perl count drops to zero. The only new state is a cached id, which is nil when it can't be read: then no owner file and no `start-` file are written, as today's fallback does. Reads of other pids stay at judging time (`architecture/lock-reads-live-state`).
Recommendation: compute `local myStart = fence.startOf(myPid())` once (in `takeLock` before the loop, passed to `takeOverIfStale`, or at module level for the top process), and use it for the owner file and for `start-<me>`. Add a non-sequestered spec (for example in `tests/tooling/`, using reuse.spec's stand-in perl that logs the pids it is asked about): a run waiting on a live, matching holder for about 1 s asks the reader for its own pid at most once. Optionally, a case with a stand-in that sleeps on the reader proves that a second waiter neither crashes nor clears the first one's mutex.
Lesson: testing/count-calls-in-poll-loops

### F2 [low] No c0127 case pins that a live top-process record with a matching id holds
Where: tracker/issues/active/c0127/acceptance/reuse.spec.luau (Rules and mutants row "each record is judged by its own id")
Evidence: mutant (1) above makes every live run's `pid` record look reused, so a second run takes the lock over from a live first run. All 13 reuse.spec cases still pass, because the top-record case only tests a reused id and every "still holds" case puts the live pid in `pid-<n>`. Only c0058's two-waiters case catches it, and only by side effect.
Critique: this is the property whose failure let two runs share `.cache` before. It is guarded today only by a promoted spec written for something else. The sequestered spec can't be changed in execution.
Consequences: none beyond one added case.
Recommendation: add a non-sequestered case (beside F1's spec): a live pid in `<lock>/pid` with its matching id in `start-<pid>` is waited for and named in "gave up".

### F3 [low] c0122 stays open in the backlog though c0131 delivers its outcome
Where: tracker/rafts/active/R0047/R0047.md, "Addressed during execution" ("c0122 can be closed as superseded"); tracker/issues/c0122/c0122.md (status `new`)
Evidence: nothing on the branch closes or links c0122, so a later prep can pick it up and redo c0131.
Critique: this is a tracker loose end, not a code defect. The lead should say it in the final report so the user can close c0122 (or have the lead do it, if the tracker allows) in the same landing.
Consequences: none.
Recommendation: name c0122 as superseded by c0131 in the PR body and the final report, and close it the way the tracker skill allows.

### F4 [low] c0131's accept.spec header describes refusals it doesn't test
Where: tracker/issues/active/c0131/acceptance/accept.spec.luau:1-6
Evidence: the header says "c0131 AC1: … and refuses everything it refused before: …", but those cases are in refuse.spec (AC2). The two headers are copies from before the split into two files.
Critique: clarity only. The file is sequestered for this PR, so fix it after promotion, if at all.
Consequences: none.
Recommendation: leave it as it is in this PR, and mention it in the final report as a candidate tidy-up after promotion.

Lesson candidates (for the lead): a guard's own facts (a process's own start id, its own pid) are read once, before any loop or claim, so the window between claiming something and recording the claim stays a single write (from F1).

Verdict: changes

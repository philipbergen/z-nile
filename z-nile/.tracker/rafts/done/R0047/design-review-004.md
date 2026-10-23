# Review 004: R0047 (design mode)
Inputs: prep worktree cee46313 (origin/main) / 8146a7c7 plus its uncommitted R0047.md, c0127.md, c0127/check.sh, c0127/acceptance/{rules,reuse,skill}.spec.luau, harvest.md, design-review/refute 001–003 and the lessons changed in answer to round 3; R0047/check.sh; capture 77aa4fa3; c0075.md (R0039, prepared); prototype `proto-c0127` on `exp-c0127-linux` a8040685 (merge base 0031e467; nothing under `tests/`, `scripts/` or the testing skill changed on origin/main since). On the prototype: rules + reuse gave `13 passed, 0 failed`. N6 (the id read before the alive check) failed exactly the read-count case (`9 passed, 1 failed`), as E4 says. The unlisted-as-run mutant "the takeover waiter writes no id" passed rules, reuse and c0058's lock.spec, `22 passed, 0 failed` (F3). `perl -e` costs about 2.5 ms a call here, so the one read per guarded process is cheap. Each mutant was restored with `git checkout HEAD --`, and the prototype's tree is clean.

Round 3 answers:
- F1 holds. The user chose start ids compared for equality (c0127 Problem, 2026-10-22). No clock enters the rule. The macOS reader reads `p_starttime`, which is stamped at fork. The Linux reader reads `boot_id` plus field 22, which is the 20th field after the last `)`, and the index is right.
- F2 holds (the read-count case kills N6, re-run above).
- F3 holds (reuse.spec line 71 refuses only `"$3" = <pid>`).
- F4 holds (AC5's text and label).
- The three lessons changed in answer to round 3 (`testing/count-calls-in-poll-loops`, `ticket-prep/accepted-risks-checked-and-decided`, and the new last paragraph of `architecture/clock-before-subprocess`) are each a rule another raft could break. None of them just restates a finding.

### F1 [high] R0039 adds a fourth pid writer, the launcher, that the merge rule doesn't cover, and R0039's pid namespace turns c0127's recording case red
Where: R0047 Order & dependencies ("R0039 … adds `pidns` and `fence.recordsPid` to how pids are *recorded* … the id is written only where the pid is"); c0127 Design, Writers (three writers); reuse.spec "a run records the start ids…" and RECORD_PROBE (lines 144–169, 208–218); c0075.md lines 92–95 (R0039: "the launcher records itself … `REAPER`, before it forks, creates `<lock>/pid-<launcher pid>` with `O_CREAT|O_EXCL|O_NOFOLLOW` … On macOS it is one more live pid")
Evidence:
- R0039 is prepared. It makes the launcher (`perl -e REAPER`, a child of the top) write `pid-<launcher pid>` on every platform. That write is in perl, so it can't call `recordStart`.
- Neither R0047 nor c0127 names this writer. c0075 doesn't mention c0127 or start ids.
- Once both rafts land, every lock has a launcher record with no `start-<pid>` file. The rule treats that record as coming from an older runner, so it holds while its pid is alive.
- On Linux under bwrap, the guarded workers record nothing (`recordsPid`). A lock there holds just two records: the top and the launcher.
- When a run crashes, a reused launcher pid keeps the lock waiting 240 s. That is the captured defect, back for every lock R0039 writes. The c0058 case "top killed, specs still run" means the launcher's record is the one the rule leans on.
- The recording case goes red after the merge, whichever raft lands second:
  - macOS: the probe sees `pid-<launcher>` with an empty recorded id and emits `worker false`. Line 216 requires that `worker false` never appears.
  - Linux bwrap: the probe runs inside the jail's private `/proc`. There `fence.startOf(<top's host pid>)` is nil, so it also emits `top false`.
- If R0047 lands first, R0039's executor meets a promoted c0127 spec that their branch turns red. R0039's `Overrides:` doesn't name it, and they may not edit it.
Critique: the "Order & dependencies" paragraph describes R0039's change as `pidns` and `recordsPid` only, and misses the launcher's own record. The tempting fix is one more sentence: "whoever lands second also writes the launcher's id". That leaves two things open: how a perl writer gets the id, and the recording probe's inside-the-jail view, which no sentence fixes.
Consequences:
- The launcher can record its own id with STARTED's logic on `$$`, written before its `pid-<$$>`. That puts perl id code in two places, so the "one reader per format" lesson applies: build REAPER's code from the same source string, or have the launcher run STARTED.
- The recording case can't judge the top from inside a pid namespace. It has to judge from the outer spec, which runs in the host namespace, while the run still holds the lock. c0058's lock.spec already uses this shape: a probe that signals it's held, waits for a go file, and the outer spec reads the lock meanwhile.
- c0075's document has to carry the matching rule. R0039 is prepared, so changing it is the lead's coordination with that raft, not this raft's executor's.
Recommendation:
- Name the launcher in R0047's Order & dependencies and in c0127's Writers as a fourth writer (after R0039).
- Rework the recording case now, in prep, while it is still editable. The probe holds the run, as in c0058. The outer spec lists every `pid`/`pid-<n>` record and requires each to have a non-empty `start-<pid>` equal to `fence.startOf(pid)` read from outside.
- Today that covers the top and the workers. After R0039 it also covers the launcher, on both platforms, and makes the missing launcher id a red case.
- Record in c0075 (through the lead) that REAPER writes `start-<$$>` (STARTED's code, from the same source) before `pid-<$$>`. Also record which raft's executor carries it if R0047 lands first.
- Re-run the case and N9/N10 on the prototype.
Lesson: ticket-prep/design-the-execution-window

### F2 [medium] The takeover mutex's owner is judged from two files read at different moments, so a normal handover makes a live owner look reused and its mutex gets removed
Where: c0127 Design, Readers ("The takeover mutex's owner is cleared when it no longer `stillHolds` against `<lock>.takeover/start`"); prototype `takeOverIfStale`, the `not mkdir mutex` branch
Evidence: waiter W2 runs `owner = readMaybe(mutex/pid)`, then `fs.metadata`, then `stillHolds(owner, mutex/start)`, which spawns `kill -0` before it reads `start`. That gap is milliseconds.
- If the owner W1 finishes inside that gap, it removes the mutex and goes on living, now running its suite.
- If W3 then claims a new mutex and writes `pid` and `start` before W2 reads `start`, W2 compares W1's id now with W3's recorded id. They differ, so W2 runs `pcall(fs.removeDir, mutex)` and removes W3's live mutex.
- The old code read one file and asked `alive(W1)`. That stays true for a waiter that moved on, so only a dead previous owner could cause this. The new rule turns every handover with three waiters into the window.
- This breaks the invariant the comment states ("Only the holder of the takeover mutex removes a lock, so two waiters can never both remove one"), which c0058's "two runs waiting on one dead lock take it one at a time" pins.
- Turning it into two fresh-lock removals still needs a holder to die near the handover, so this is medium, not high.
Critique: the record and its id live in two files, and nothing ties the two reads to the same mutex. The tempting fix is to swap the read order. That doesn't help: whichever file is read second can come from the next mutex.
Consequences: one consistent read needs one file. A new `owner` file (`<pid> <id>`, written to a temporary name and renamed into the mutex) gives an atomic pair. The waiter reads `owner` when it exists and otherwise falls back to `pid` with `alive` (an owner from an older runner, or the moment before the rename). `pid` stays as it is for older runners. A cheaper alternative: re-read `pid` after `start`, and treat a change as "holds this step". That leaves only a two-handover ABA, which is negligible.
Recommendation: pick one of these and state it in the Design, with a Rules and mutants row. Add a reuse.spec case that hand-builds a mutex whose `start` belongs to another live process while `pid` names a live spec-owned process with no `owner` file, and asserts the mutex is kept. The mutant is "owner judged against a `start` that isn't its own".

### F3 [medium] The takeover waiter's own id write has no case, and without it a reused pid of a crashed waiter blocks the lock exactly as in R0034
Where: c0127 Rules and mutants, row "the takeover waiter records its id" (reasoned: "judged as from an older runner (alive holds), today's behaviour")
Evidence: I removed `recordStart(`{mutex}/start`, me)` on the prototype. rules, reuse and c0058's lock.spec gave `22 passed, 0 failed`. With that mutant, a waiter killed while holding the mutex (the case c0058's "a takeover left by a waiter that died" covers) leaves `takeover/pid` with no id. If that pid is reused, the owner holds while the reused process lives, the mutex is never cleared, and every later waiter waits out its 240 s. "Today's behaviour" is the captured defect, moved one file over.
Critique: the row's reasoning treats the mutant as harmless, but it is the Problem for the mutex. The tempting fix is to leave the row reasoned. It can be run end to end.
Consequences: the takeover window is observable already: `PICKMAN_TEST_TAKEOVER_PAUSE` holds a waiter between judging a dead lock and removing it.
Recommendation: add a reuse.spec case. Start a run in the background against a dead lock with `PICKMAN_TEST_TAKEOVER_PAUSE=3`, wait for `<lock>.takeover/pid`, then assert that `<lock>.takeover/start` equals `fence.startOf(<that pid>)` read by the spec. Mark the row `run`, with the mutant above recorded in E4. If F2 moves the pair into `owner`, assert on that file instead.
Lesson: testing/pin-fail-safes-where-they-act

### F4 [low] "Between a pid and its id being written … never a false takeover" is false for a pid reused within one lock
Where: c0127 Design, Writers (last sentence); Writers order ("each records its id right after its pid")
Evidence: lock records are never removed during a run. Suppose a guarded process X1 recorded `pid-X` and `start-X` and has exited, and a later guarded process X2 gets the same pid X (round 3 measured about 1,800 pids a second, so macOS wraps in about a minute of a gate). X2 writes `pid-X`, which is already there, and then `start-X`. In between, `start-X` still holds X1's id while X2 is alive, so X is judged reused. This only matters when no other record holds, for example in c0058's "top killed, specs still run" state with one remaining spec process. The window is a perl run long.
Critique: the risk is tiny, but the Design states the opposite as a guarantee.
Recommendation: write the id before the pid, at all three writers (and at the launcher's, F1). A fresh pid then has no record until its id exists. A reused pid's record already exists, so its new id arrives before any waiter could pair it with the old one. The top's and the mutex's windows stay the same as today's (no record yet, so the unowned rule applies). Correct the sentence. An order pin on `fence.enter`'s guarded branch is enough as its case (testing/order-pins-anchor-unique-text).

Verdict: changes

## Lesson candidates (for the lead)
- ticket-prep: when another prepared raft changes the same mechanism, list every writer and reader it adds, not just the gate it adds. Reason: R0047's merge note named R0039's `recordsPid` but missed R0039's launcher, which writes a pid record from perl, outside every helper this raft changed. Check: for each other raft that touches these files, has its design been read for every new write and read of the data this raft's rule depends on, and does each sequestered spec still pass with that raft merged?
- architecture: a fact read from two files is only consistent if the two files can't belong to different owners between the reads. Write the pair to one file atomically (temporary name and rename), or re-read the first file to confirm it, because R0047's mutex judged one owner's pid against the next owner's start id. Check: where a decision reads two files about one holder, can the holder change between the reads, and what does the decision do then?

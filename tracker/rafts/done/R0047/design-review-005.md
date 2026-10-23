# Review 005: R0047 (design mode)
Inputs: prep worktree 8146a7c7 (origin/main 0cf01e2f) plus its uncommitted R0047.md, c0127.md, c0127/check.sh, c0127/acceptance/{rules,reuse,skill}.spec.luau (identical to the prototype's `tests/acceptance/c0127`), harvest.md, design-review/refute 001–004, the lessons changed in answer to round 4, the R0039.md note (`git diff origin/main`), c0075.md and its sequestered `acceptance/{launcher-lock,live-jail}.spec.luau`; capture 77aa4fa3; prototype `proto-c0127` on `exp-c0127-linux` 4937b42e.

Spot runs on the prototype (each mutant restored with `git checkout HEAD --`; the tree is clean):
- O2 (the waiter writes no owner file): reuse.spec `10 passed, 1 failed`, the owner-file case. Matches E4.
- M1 (`ownerHolds` returns false when there is no owner file): reuse.spec 11/11 and c0058's lock.spec 9/9 still pass (F2).
- M2 (`ownerHolds` compares `id == fence.startOf(pid)`, so an unreadable id means "not holding"): reuse.spec, rules.spec and lock.spec 11/11, 3/3 and 9/9 still pass (F2).

Round 4 answers:
- F2 holds. With pid and id in one `owner` file, a handover between the read of `pid` and the read of `owner` judges the new owner consistently. A missing `owner` falls back to `alive` of the old `pid`, which keeps the mutex.
- F3 holds (O2 re-run above).
- F1 is answered only in part. The writer is named, but the rule handed to R0039 can't be followed (F1 below).
- F4 is not answered. Writing the id first changes nothing for a pid reused within one lock (F4 below). It stays low.
- The lessons: `architecture/read-paired-facts-at-one-moment` is a general rule that another raft could break, so it is good. The extended check of `ticket-prep/design-the-execution-window` asks about "this raft's sequestered specs" only, and so misses the defect in F1 (lesson candidate).

### F1 [high] The merge rule for R0039's launcher can't be followed in either order: an id file in the lock turns c0075's `launcher-lock.spec` red, and R0047's `Overrides: none` doesn't name it
Where: c0127 Design, Writers ("Any other writer…"); R0047 Order & dependencies; the note this prep adds to R0039.md; `tracker/issues/c0075/acceptance/launcher-lock.spec.luau:15,43`; c0127 `Overrides: none`
Evidence:
- c0075's sequestered AC3 case "records its own pid in the lock while the command runs" runs `ls "$2"` on the lock while the launcher's command runs. It then asserts `t.expect(ls).toBe(`pid-{ppid}`)`: the folder must hold exactly one name.
- The rule both rafts now carry says the launcher "writes `start-<pid>` whole before its record". The folder then lists `pid-<ppid>` and `start-<ppid>`, and the case fails.
- R0047 lands first: R0039's executor must add the id write. That turns red its own sequestered AC3 case, which it may not edit. If it leaves the write out, R0047's promoted `reuse.spec` recording case goes red instead (`worker false` for the launcher on macOS). Either way the executor has to stop and escalate.
- R0039 lands first: R0047's executor adds the write to `REAPER`. That turns red the promoted `tests/acceptance/c0075/launcher-lock.spec.luau`. c0127's `Overrides:` says none, and the Affected specs don't list it.
- R0039 is prepared, not merged, so this is still a real execution path. Review 004 F1 found the first hole in this cross-raft mechanism, and this is the second.
Critique: the fix rewrote the documents but didn't run the other raft's specs against the rule it hands them. The tempting fix is to add the c0075 spec to an `Overrides:` line "if R0039 has landed". That covers one order only. In the other order, R0039's sequestered spec still blocks its own executor.
Consequences:
- Any extra name in the lock folder breaks that case. So either the launcher's id goes somewhere other than a new file in the lock, or c0075's case changes now, in prep, while R0039 is still only prepared.
- Changing c0075 is a change to another raft's reviewed, sequestered spec. It needs R0039's lead, and a check (or re-review) of that one case.
- Putting the launcher's id inside its record changes this raft's reader. The record would be `pid-<n>` created whole (a temp name, then a rename) holding the id. The reader would then take the id from `start-<pid>` or else from the record's content, which is a second format.
Recommendation:
- Escalate to the user, as the last round's high, with the options:
  - (a) Amend c0075's `launcher-lock.spec` case now (through R0039's lead) so it ignores `start-*` names: for example, it asserts the `pid-*` names equal `{pid-<ppid>}`. Add a c0075 case that the launcher's `start-<ppid>` equals the reader's id when R0047 has landed. Cost: one change to R0039's sequestered spec and a narrow re-check of it. No change to R0047's design.
  - (b) Give every non-top record its id as the record's own content, written whole: `pid-<n>` holds the id, and `start-<pid>` is kept for the top only. Then `ls` is unchanged for the launcher. Cost: a redesign of the Writers and Readers, a reworded Non-goal, and the round-4 cases re-run.
- Whichever is chosen, fix R0047 and R0039's notes together. List `tests/acceptance/c0075/launcher-lock.spec.luau` in c0127's Affected specs. Make the `Overrides:` line true for the R0039-first order. Run c0075's launcher-lock case against the merged rule on the prototype, by cherry-picking or reproducing R0039's REAPER record there.
Lesson: ticket-prep/design-the-execution-window

### F2 [medium] The owner's two fail-safes (no `owner` file, an id that can't be read now) have no rows and no cases, and both mutants pass every check
Where: c0127 Design, Readers (`ownerHolds`); Rules and mutants (the owner row covers only "judged by `alive` only"); prototype `fence.luau:212-218`
Evidence:
- M1 makes `ownerHolds` return false when `owner` is missing.
- M2 makes it compare `id == fence.startOf(pid)`, so an unreadable id means "not holding".
- With either mutant, rules, reuse and c0058's lock.spec all pass (spot runs above).
- What each mutant breaks:
  - M1: a live waiter whose own id couldn't be read (it writes no `owner`), or one from an older runner, has its mutex removed by the next waiter. That breaks "only the holder of the takeover mutex removes a lock".
  - M2: the same happens for any owner whose id can't be read at judging time.
- Two waiters can then both judge and remove a lock, a fresh one included. That puts two runs on the same `.cache`.
- `stillHolds` got end-to-end cases for exactly these two fail-safes (rounds 2 and 3). `ownerHolds` is a second place where they act.
Critique: the tempting answer is "`fence.holds` is unit-tested". But M2 bypasses `fence.holds` at the call site, which is the N5 shape round 2 required pinned. These are not high, because both states (no readable id for a waiter in the host namespace, or a mixed-version runner in one checkout) are rare.
Consequences: both cases can be built with what reuse.spec already has. A hand-built mutex holds the dead lock behind it, and the run must give up (LOCK_WAIT=1) with the mutex and the lock still there.
Recommendation:
- Add two reuse.spec cases, and two `run` rows killing M1 and M2:
  - "a takeover with only `pid`, naming a live pid, is kept": `takeover/pid` names a spec-owned `sleep`, there is no `owner`, and the lock behind it is dead.
  - "a takeover whose owner's id can't be read now is kept": `owner` is `<live pid> 1.0`, and `standIn(<that pid>)` refuses the reader.
- Record M1 and M2 in E4.
Lesson: testing/pin-fail-safes-where-they-act

### F3 [medium] Nothing says R0039's `recordsPid` gate must cover the id write. Placed before the gate, jailed processes overwrite `start-<top>` and `start-<launcher>`, and a live run's lock is taken over on Linux
Where: R0047 Order & dependencies ("its hunks sit next to R0039's `recordsPid` gate … whoever merges second keeps both"); c0127 Design, Writers ("`fence.enter` in a guarded process: `start-<me>`, then `pid-<me>`"); the R0039.md note
Evidence:
- Under R0039, the guarded branch writes `pid-<n>` only when `fence.recordsPid(...)`.
- The documents say only "the id before the record". A merge that keeps R0047's `recordStart` line ahead of R0039's `if` then has every jailed lune write `start-<N>`, where N is its pid in the namespace, together with its own id (`/proc` inside the jail shows itself).
- A full gate spawns thousands of processes in one namespace, so N counts up through the small host pids that a top and a launcher get on a fresh CI VM or Linux box.
- When N equals T or L, `start-T` or `start-L` becomes a jailed process's id. The live top or launcher is then judged reused.
- A second run in the same checkout then finds no holder and takes over the live lock.
- No spec catches this: reuse.spec's held run spawns a handful of jailed pids, and live-jail checks only `pid-<own>`.
Critique: it is not high, because it needs both the wrong merge placement and a second run in one Linux checkout. But it is the 2026-09-30 failure, and the fix is a sentence. The tempting sentence, "keep both hunks", is what produces the defect.
Consequences: the rule is "the id is written only where the record is written". Its pin is an order/position check in R0039's merged guarded branch (testing/order-pins-anchor-unique-text). Or a live-jail assertion: no `start-<own>` inside the jail under bwrap, next to its `pid-<own>` check.
Recommendation:
- State in c0127's Writers, R0047's Order & dependencies and the R0039 note: "the id is written inside the same condition as its record: no record, no id".
- Name the pin that the raft landing second adds: the live-jail line `table.find(names, `start-{own}`) == nil` under bwrap, or a source-order check.

### F4 [low] (repeat of design-review-004 F4) "Writing the id first means a record is always judged by the id its own process wrote, even when a pid is reused within one lock" is still false
Where: c0127 Design, Writers (second sentence); Rules and mutants row "the id is written before the record" (its reasoning)
Evidence:
- Records are never removed during a run: there is no `removeFile` of `pid-*` in `fence.luau`. When X2 reuses X1's pid inside one lock, `pid-X` (X1's record) already exists from the moment X2 starts.
- From X2's exec until its `recordStart` finishes (lune startup, `fence.enter`, one perl run), a reader sees `pid-X`, `alive(X)`, and X1's id in `start-X`, so it answers "reused".
- The order of X2's two writes doesn't touch that window. Id-first and record-first give the same window. The row's claim that the order matters "when a pid is reused within one lock" is the wrong way round.
- It is harmless only because X2's spawner is itself a live recorded member that holds.
Critique: this is the same mechanism review 004 F4 questioned. The fix answered it by reordering writes, which can't help, because the stale half of the pair is the record, not the id.
Recommendation:
- Correct the sentence and the row to the real argument: "a member reusing a pid recorded earlier in the same lock looks reused until it writes its id; its spawner's record holds meanwhile, so the lock is held".
- Keep id-first (it is harmless) and mark the row "reasoned: order irrelevant".
- No new mechanism is needed.
Lesson: architecture/read-paired-facts-at-one-moment

Verdict: changes

## Lesson candidates (for the lead)
- ticket-prep/design-the-execution-window (extend its check again): when this raft hands a rule to another prepared raft, run **that** raft's sequestered and promoted specs against the rule, not only this raft's. Reason: R0047 told R0039's launcher to write `start-<pid>` into the lock, and c0075's sequestered `launcher-lock.spec` asserts the lock lists exactly `pid-<ppid>`. Check: for each instruction this design gives another raft, which of that raft's specs read the state the instruction changes, and do they still pass?
- testing: a fail-safe pinned in one reader must also be pinned in every other reader that applies it, because R0047 pinned "no id / unreadable id holds" for lock records but not for the takeover's owner, where both mutants passed. Check: list every call site that applies a fail-safe. Does each have an end-to-end case that fails when that site alone drops it?
- architecture: when a guard's write is gated (here, by pid namespace), every write that belongs to the gated record goes under the same gate, because a companion file written outside it can overwrite a real holder's data. Check: for each companion write, is it under exactly the condition of the record it belongs to?

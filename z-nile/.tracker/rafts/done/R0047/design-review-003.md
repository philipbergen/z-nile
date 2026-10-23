# Review 003: R0047 (design mode)
Inputs: prep worktree 8146a7c7 plus its uncommitted R0047.md, c0127.md, c0127/check.sh, c0127/acceptance/{rules,reuse,skill}.spec.luau, harvest.md, design-review/refute 001 and 002, and the six new or changed lessons; R0047/check.sh; capture 77aa4fa3; prototype `proto-c0127` on `exp-c0127-linux` b8a1b4bf (base 0031e467; nothing under `tests/`, `scripts/`, `.github/` or the testing skill changed on `origin/main` since). CI run 39726475139: `workflow_dispatch`, head b8a1b4bf, success, `2048 passed, 0 failed, 301 spec files`. On the prototype: rules, reuse, skill and c0058's lock.spec gave `20 passed, 0 failed`. M11 (`stillHolds` returns false on a nil start) fails only the unreadable-start case (`6 passed, 1 failed`), as E4 says. One unlisted mutant survived (F2). Each mutant was restored with `git checkout HEAD --`, and the prototype's tree is clean. Its `.cache/c0127/` copies predate this review and were left alone.

Round 2 answers:
- F1 holds. The new case kills M11 end to end, and it fails red, not vacuously, when the stand-in isn't reached, because the real reader then answers and the backdated lock is taken over. It deviates from the recommendation in one way: it refuses the call for every pid (F3).
- F2 does not hold: the accepted risk rests on a false premise. Repeated as F1.
- F3 holds. E7 ran on ubuntu, AC5 follows c0001's AC3 form, and a raft branch's dispatched run executes `active/*/acceptance` (check.yml).
- F4 and F5 hold.

### F1 [high] (repeat of design-review-002 F2) The clock-step risk is accepted on a false premise, and it is a new way for the lock to be taken from a live run
Where: R0047 Risks, first bullet ("Linux runs today are one-gate CI jobs where nothing waits"); c0127 E5 ("Accepted: … Linux runs today are CI jobs"); Non-goals ("No new field is recorded"); review skill, design item 9
Evidence:
- `SETUP.md` gives Linux as a supported host, with a Linux column in Prerequisites. R0039 (prepared) exists to jail local Linux runs, so local Linux gates are expected.
- On such a host the lock does what it does on a Mac: an agent's gate, the Stop hook's run and `tracker.sh done`'s gate share one checkout.
- Linux specs are unjailed (testing skill, "Linux (CI)"), so the lock is one of the few guards there.
- The new rule adds a failure the old one didn't have. Before, a live pid always held. Now, on Linux, a forward wall-clock step of more than 2 s at any moment while a run holds the lock makes `btime + ticks` jump past every record's mtime, and the next waiter removes a live lock.
- Typical triggers: timesyncd stepping after a resume, a VM or WSL resync, a manual `date`.
- The raft's own text says what follows: two runs share `.cache` fixtures, "which is how a spec once reached the real repository".
- Item 9 makes any weakening of a guard high. The author accepted this risk, not the user.
Critique: round 2's answer fixed the wording but kept the mechanism: the rule orders a start time against a file time, so either clock moving breaks it. The tempting fix is to reword the premise ("rare on Linux hosts too") and accept again. That leaves the hole, and an author still can't accept a guard weakening.
Consequences:
- A larger slack is no answer here. I measured pid allocation on this Mac during two specs at 16,437 pids in 9 s (about 1,800 a second), so macOS's 99,999 pids wrap in about a minute under a gate. A reused pid that started soon after its record is therefore plausible, and a slack of tens of seconds would leave R0034-like locks blocking again.
- The mechanism that has neither problem identifies a holder by its (pid, start) pair. When the record is written, store the process's start as the reader gives it: macOS `p_starttime`, which is fixed for the process's life, and on Linux the raw field-22 ticks, which are on the boot clock. Later, a recorded pid holds only while its current start equals the stored one. Equality involves no clock, no slack and no step.
- That writes a new field, which the Non-goals exclude. That exclusion is the author's own fence, not captured scope (the capture names "start time").
- New edge cases come with it:
  - Older locks have no stored start (`pid-<n>` is empty today) and fall back to the current mtime rule.
  - `fence.enter()` runs perl once per guarded Lune, about 370 per gate at about 5 ms each, spread across processes.
  - A record whose start couldn't be read at write time also falls back.
  - The takeover's `pid` needs the same treatment.
Recommendation: escalate to the user, with these options:
- (a) Record the start in each record (`pid` line 2, `pid-<n>` content, `<lock>.takeover/pid` line 2) and compare for equality, falling back to the mtime rule for records without one. This needs new Rules and mutants rows (equal holds, different does not, a missing stored start falls back), a reuse.spec case with a stored start that differs while the mtime is old, a case for an old-format record, a measured cost for `enter()`, and the Non-goal rewritten.
- (b) Keep the mtime rule and have the user accept the Linux forward-step risk, as a `Decided with the user (date)` line in Risks with the premises corrected (Linux hosts are supported; R0039's jail is not merged).
- (c) Keep the mtime rule on macOS only, and use the old alive-only rule on Linux. This narrows the fix on Linux, which is a scope decision for the user.
Lesson: architecture/clock-before-subprocess

### F2 [medium] "The start is read only for a pid that is alive" has no Rules and mutants row, and its mutant passes every check
Where: c0127 Design (`stillHolds`: "The start is read only for a pid that is alive"), Scalability ("the dead ones cost a `kill -0` each, as today; only the few live ones run perl"), Rules and mutants table
Evidence:
- On the prototype I changed `stillHolds` to call `fence.startedAt(pid)` before `alive(pid)`. Then rules, reuse and c0058's lock.spec gave `19 passed, 0 failed`.
- The mutant runs perl for every dead record, about 370 in R0034's lock, at roughly 5 ms each, on every 0.1 s wait step until a holder is met. `fs.readDir` order isn't sorted, so the top `pid` needn't come first.
- `takeLock` counts `waited += 0.1` per step, not wall time. So the 240 s limit stretches by the scan's cost, about 2 s a step, which could mean over an hour, far past the Stop hook's 300 s budget the default exists for.
Critique: the Design states the rule and leans on it for Scalability, but nothing pins it. The tempting fix is a code comment, which pins nothing.
Consequences: counting calls needs a way to observe them. The stand-in perl that F3 tightens can log each STARTED call's pid to a file in the fixture's `.cache`. The case then asserts the log holds only the live pid, never the dead `pid` record. That log also proves the stand-in was reached.
Recommendation: in the unreadable-start case, have the stand-in append `$3` to `{base}/started.log` before exiting 1. Assert the log is non-empty and every line equals the live pid. Add a row "the start is read only for a live pid" with the mutant above, run it on the prototype and record it in E4.
Lesson: ticket-prep/spec-design-correspondence

### F3 [low] The stand-in perl refuses the reader's call for any pid, not the one it was set up for
Where: reuse.spec `refuseStartReads`, line 72; design-review-002 F1's Recommendation ("fails the STARTED call for that pid only"); testing/stand-ins-answer-only-named-arguments ("the target id it was set up for")
Evidence: the match is `$1 = -e`, `$# = 3` and a 40-character program prefix. `$3` is never checked, so a refusal for the mutex owner's pid or for perl's own `$$` looks the same as one for the recorded pid. No surviving mutant exploits it today (the other cases catch wrong-pid reads), but the case breaks the lesson written in answer to round 1.
Recommendation: pass the live pid to `refuseStartReads(pid)` and refuse only when `"$3" = <pid>`. Run the real perl for every other pid, including other STARTED calls. Combine this with F2's log.
Lesson: testing/stand-ins-answer-only-named-arguments

### F4 [low] Nothing tells the executor that AC5 dispatches CI and needs the head pushed every time c0127's check runs
Where: c0127 Implementation steps 5 and "Before done"; check.sh AC5; R0047 RC0 (`bash "$dir/check.sh"` inside `tracker.sh done`); review skill code mode item 1 (the reviewer runs `tracker.sh check <id>` itself)
Evidence: every `tracker.sh check c0127` runs `scripts/ci-verify.sh`, which fails unless `HEAD == origin/<branch>`, then dispatches a ubuntu run and waits for it (several minutes).
- It runs on the executor's pre-done check.
- It runs again inside `done`'s RC0.
- It runs again for the code reviewer, who is briefed not to push and gets a red AC5 whenever the author's last commit isn't pushed.
- A stream worktree's `ws-c0127` branch is never on origin.
Recommendation: state this in Implementation step 5 and the "Before done" line: each check run dispatches CI and needs a pushed head, and a stream or reviewer run reads a red AC5 on an unpushed head as "push first", not as a defect.
Lesson: ticket-prep/instructions-runnable-where-they-run

Verdict: changes

## Lessons from harvest.md
- testing/stand-ins-answer-only-named-arguments, testing/narrow-guard-allowances, testing/pin-fail-safes-where-they-act and ticket-prep/fallbacks-name-the-modes-they-cover are each general enough for another raft to fail. None is a restated finding.
- architecture/clock-before-subprocess is now correct about Linux's rebuilt start. It should also point to the answer F1 describes: compare identities (a value stored at record time and compared for equality) rather than ordering two clocks.
- The new platform clause in ticket-prep/prove-specs-pass-on-a-prototype is a real generalisation.

## Lesson candidates (for the lead)
- testing: a polling loop that counts steps rather than wall time makes each step's cost part of its timeout, so a subprocess added to the step needs a pinned call count, because c0127's start read could run once per dead record per step and stretch the 240 s wait by about 20 times with every spec green. Check: for each subprocess added inside a wait or poll loop, does a spec count its calls?
- ticket-prep: an accepted risk states premises that can be checked against the repo (supported hosts in SETUP.md, which guards exist where), and a risk that weakens a guard is accepted by the user, not the author, because R0047 accepted a Linux live-lock takeover on "Linux runs are CI only", which SETUP.md contradicts. Check: does each accepted risk's premise hold against SETUP.md and the skills, and does a guard-weakening risk carry a `Decided with the user` line?
- architecture: identify a thing by a value stored when it was recorded and compared for equality ((pid, start), (inode, mtime)), not by ordering one clock's time against another's, because equality survives clock steps and needs no slack. Check: where a design decides "same or different" by comparing two times, could it store one side and compare for equality?

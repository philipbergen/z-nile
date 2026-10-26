# Review 005: c0117 (design mode)
Inputs: `prep-c0117` at e750525 (`z-nile/.tracker/issues/c0117/{c0117.md,check.sh,harvest.md,acceptance/*}`, `design-review-004.md`, `design-refute-004.md`, the two new lessons `several-writers-check-the-subject` and `waiting-steps-show-liveness`, and the amended `guard-state-out-of-reach-or-checked` and `merge-gate-checks-what-it-merges`); prototype `.worktree/proto-c0117` at f17b19e on b57df84, read only; `./zn capture c0117` (fb7fd80, no marker); `./zn lessons --when design --full`. Every attack ran in scratch clones of the prototype under the session scratchpad (`c0117-review005/clone`, `c0117-review005/mut`), origin pointed at a path that doesn't exist, through `lune run tests/run` (the jail), in `.cache/` fixtures; one plain-git race ran in a scratch folder of its own (`c0117-review005/race`, a bare origin and a clone, commits as `@example.invalid`). No real CLI, no network, no real origin, no branch, worktree or commit in the real repository.
Dropped from review-004: F1, F2, F3, F4, F5. Each fix holds against round 4's own reproduction (below).

The bar this round is the user's "Keep same user, accept detection": every guard detects mistakes, and a determined agent rewriting what it can reach is a documented limit. The findings below are ordinary use.

Scope (item 11): the capture is confirmed and unchanged since round 4. The Problem is the capture's, word for word. The round's edits add detail only (§5's liveness paragraph, the watermark's shared-file rules, §6's block-style `issues:` note, G22, E15). Every captured outcome still has a Design and a criterion. AC10 now criterions "chains the steps … up to the pull request" with a nested review longer than `tool_seconds`.

Round 4 rechecked (against f17b19e):
- **F1, concurrent dispatchers.** I reran round 4's `conc` spec unchanged except for its expectation. B's long step runs while the other terminal publishes tracker state and runs A to completion. Now **B exits 0** (`ok / done`) and A exits 0. W1 and W2 still trip, on `w1.lua` and `w2.lua`, from the run's in-memory mark. `advanceMark` takes an flock, writes only forward and trips on a diverged file. The mirror check reads the shared file only at the start. Holds.
- **F2, the heartbeat.** `runner.run` writes `<stateDir>/beat` while its own CLI prints, and only when it is nested (`beatFile` only when not serving). Every runner reads its direct child folders' beats once a second, and a changed beat resets `quiet`. A nested step's own children's beats reset its `quiet`, so it beats in turn and the signal goes up through every level. `STEP_ENV["claude-cli"]` reaches the step's environment (`bashmax=7200000` shows in every fake log of my runs). The control-cli case drives an author that waits on its review through one tool call, with `tool_seconds = 8` and a reviewer that prints for 16 s. Its quiet half (`sleep 20`) stalls the author. Holds, apart from G22's cost (F2) and a boundary race (F3).
- **F3, the rafting gate.** control-cli now drives real heads through `fakecli.pullRequest` with `auto_merge = ["raft"]`: a merge pinned to the head, and waits for code, c0091's `check.sh`, a `.models.toml` and a stale head. I reapplied round 4's mutant (`if gateName ~= "prep" then return nil end` as `judgePr`'s first line) in the mutant clone. control-cli: 21 passed, 1 failed, and the failure is the rafting gate's case. Killed. Holds.
- **F4, F5.** The lesson texts, §8 step 4, E10 and G20 now say what round 4 asked.

Round 3's reproductions still refuse, through the same specs as round 4:
- **S:** "tracker/issues/done/c0091/check.sh is sequestered".
- **GA:** `tracker/.GITATTRIBUTES` is "configuration".
- **W1, W2:** exit 5, on `w1.lua` and `w2.lua`. Before the fix, round 4 saw "the watermark changed"; now the trip names the commit.
- **MT:** `.models.toml` is "not tracker state (configuration …)".
- **V, B:** refused.
- **R:** exit 5, "origin's configuration changed during the step".
- **P3:** `calls 500`, `unknown "3 turns with no model_call_id"`.
- **Round 2's spec:** 7 of 7.

Guesses:
- **G18:** reasonable. It now names concurrent dispatchers, and case C proves it, apart from F1 below, which is the same sharing one level down.
- **G20:** reasonable under the decision. The rebase-merge cost is stated, and so is the squash-only alternative.
- **G22:** the heartbeat half is reasonable. Raising claude's limits is reasonable too, but the default half has a cost the text doesn't name (F2).

### F1 [medium] Concurrent dispatchers still share one mutable ref, `refs/zn-dispatch/main`: overlapping fetches fail with "cannot lock ref", and `vetMain` turns a failed fetch into a tripwire that stops the item
Where: `dispatcher.freshMain` (`git fetch -q <pinned> +refs/heads/main:refs/zn-dispatch/main`, then `rev-parse refs/zn-dispatch/main`); `broker.push` (the same fetch into the same `broker.FRESH`); `dispatcher.vetMain` (`if not fresh then return "origin's main could not be fetched to vet it"`) and its callers, which set `outcome = "tripwire"` (exit 5; `chain` keeps a tripwire outcome until a human retries); `dispatcher.tripwire` (after `vetMain`, `merge-base --is-ancestor after.head refs/zn-dispatch/main` reads the ref again, not the sha just vetted); §5 "The watermark and the tripwire"; G18.
Evidence:
- **Measured (plain git, scratch race folder).** One clone stood in for the shared repository. Three fetchers each ran `git fetch -q <origin> +refs/heads/main:refs/zn-dispatch/main` 300 times while a fourth process pushed 150 commits to `main`. The fetchers failed **84, 88 and 99 times**, each with `error: cannot lock ref 'refs/zn-dispatch/main': is at <X> but expected <Y>`. Git compares and swaps the ref, so a fetch fails whenever another fetch moved the ref under it. This load is far above real use, but every collision has the same cause. In real use, two dispatchers (or a dispatcher and another run's broker) fetch at the same moment while `main` moves. Each run fetches at its start, before and after every model step, and on every broker request, and with one dispatcher per item `main` moves on every claim and spend.
- **What a collision does** (code read): `freshMain` returns nil, so `vetMain` returns "origin's main could not be fetched to vet it". Before a model step or in the tripwire, that is `outcome = "tripwire"`, exit 5, and the item stops until a human retries it. In the broker it refuses the step's publish ("the dispatcher could not fetch origin's main"). The repository already knows this failure: `publish.commit` retries its fetch with back-off because "a lock held by a sibling worktree" fails it, and names a sha rather than `origin/main` because "sibling worktrees share that ref". The dispatcher's new fetches do neither.
- **A second effect** (reasoned, not reproduced). An earlier fetch that reads the ref after a later fetch has updated it can force it back, since the refspec has `+`. The tripwire then reads the ref again for its "HEAD moved only forward along main" check. If `./zn` fast-forwarded the main checkout to the newer `main` during the step, the check sees a `main` older than HEAD and trips: "the main checkout's HEAD moved … off origin's main".
Critique: round 4 F1 fixed the watermark file by making its writes forward-only under a lock. The ref the watermark is computed from is the same kind of shared record, with the same honest writers: every dispatcher of the repository and every broker. The new lesson `several-writers-check-the-subject` asks exactly "who else writes this record, and can two writers race it?". The tempting fix is to retry the fetch, as `publish.commit` does. That makes a collision rarer, but the ref can still be forced backwards between the fetch and the tripwire's read.
Consequences:
- A ref per run needs a name and a cleanup: a lost run leaves one behind.
- A retry needs a bound and a classification. A fetch that still fails after the retries is a network fault, not tampering. It should still stop the chain (it fails closed), but it should say it is a fetch failure.
Recommendation: give each run its own ref, and pass shas, not refs.
- **The ref.** `freshMain` and `broker.push` fetch into `refs/zn-dispatch/run-<run token>/main`. The broker already holds the run's token.
- **Use the sha.** `freshMain` returns the sha. `vetMain` hands it to the tripwire, whose `onMain` check uses that sha, never a ref read later.
- **Cleanup.** The run deletes its ref at its end. Each run's start (and `vet`) deletes `refs/zn-dispatch/run-*` refs whose run lock nobody holds (`runner.held`).
- **Retry.** Retry a failed fetch three times with back-off, as `publish.commit` does. A fetch that still fails stops the run with the detail "origin's main could not be fetched (network?)". It keeps today's tripwire outcome or uses `failed`; say which. `retry` clears it either way.
- **Cases (control-cli):**
  - two dispatchers whose steps each publish ten tracker commits through their brokers, at once, both exit 0 (mutant: one shared ref);
  - a fetch that fails twice, then works (a fake `git` on the step's real PATH, or a held `.lock` on the run's ref removed after 0.3 s), vets and exits 0 (mutant: no retry);
  - a lost run's leftover ref is gone after the next run starts.
- **Rows:** one Rules and mutants row per case. G18 names the per-run ref.
Lesson: architecture/several-writers-check-the-subject, architecture/lock-reads-live-state

### F2 [low] G22 raises claude's *default* command limit to two hours, so a hung command now costs the whole step at `tool_seconds` instead of a two-minute tool error the model recovers from, and G22 doesn't say so
Where: `adapters.STEP_ENV["claude-cli"]` (`BASH_DEFAULT_TIMEOUT_MS = BASH_MAX_TIMEOUT_MS = 7200000`); G22; §5 "Liveness of a waiting step".
Evidence (reasoned): take a command in a claude step that hangs without printing, such as one waiting on a prompt or a network read. Today Claude Code kills it at 120 s and the model goes on. With the default at two hours, the dispatcher's runner kills the step's whole group at `tool_seconds` (900 s). The outcome is `stalled`, and the chain stops until `retry`. Only the review command needs the long limit.
Recommendation:
- **Name the cost in G22**, with the alternative for the user to pick: raise only `BASH_MAX_TIMEOUT_MS`, and have the headless section tell the author to pass a two-hour `timeout` on its `./zn dispatch zz-review …` command. E15 settles whether claude honours that in `-p` mode.
- **If the alternative is taken**, docs.spec pins the sentence, and the control-cli case keeps its `bashmax` check.

### F3 [low] The nested beat is written only while the nested CLI prints, so a reviewer that is silent inside one tool for close to `tool_seconds` can still get its waiting author killed: both limits are 900 s, and the author sees a beat up to about a second late
Where: `runner.run` (a beat only `if r.beatFile and quiet < 0.2 and elapsed - lastBeat >= 1`; children's beats read `if elapsed >= nextScan`, once a second); the root `tool_seconds = 900`, shared by the author's walk and the reviewer's.
Evidence (reasoned): a reviewer runs one long tool, such as the full gate under load, and its CLI is silent for 899.5 s. The reviewer's own runner allows it. The author has been in its own tool call the whole time, and its limit is also 900 s. Its `quiet` reaches 900 before the reviewer's next line becomes a beat it reads, so the author's group is killed, and the live reviewer with it. The window is narrow, but a long review is exactly where the heartbeat matters.
Recommendation: a nested runner beats once a second for as long as it is alive and within its own limits, not only while its CLI prints. That is safe: the nested runner enforces its own `stall_seconds` and `tool_seconds`, so a hung reviewer is still killed at its own limit, and the beats stop when it is. Then the author's stall clock measures the reviewer's liveness, not its chattiness. The quiet-reviewer case still passes, since the nested step stalls at 8 s and its beats stop. Add a row: a nested step that is silent for longer than its author's `tool_seconds`, but within its own limit, keeps its author alive (mutant: beat only on output). The fake's `tool_seconds` for the reviewer has to be larger than the author's for that case.

Repository safety (item 9): no finding.
- The new cases run under `.cache` fixtures: `fakecli.new`, and `fakecli.pullRequest` heads pushed only to the fixture origin's `refs/pull/<n>/head`.
- `ZN_WATERMARK_DIR` is set in `fakecli.zn`.
- The watermark lock is a file in the fixture's watermark folder.
- The two-hour `STEP_ENV` affects only a step's environment.
- `check.sh` is unchanged in kind: it runs specs through `tests/run`, plus read-only checks.

Lessons (item 10): I asked each design lesson's check of the round's delta. F1 repeats the new `several-writers-check-the-subject`: the watermark was fixed, but the ref it is computed from has the same writers. It also repeats `lock-reads-live-state`. The two new lessons generalise beyond c0117, and so do the two amended ones. None is a restated finding.

Candidate lesson (for the lead): a heartbeat should say "alive and within my limits", not "printing". Check: if the child is silent but healthy for as long as the parent's own limit, does the parent survive? This may fit as a note on `waiting-steps-show-liveness` rather than a new file.

Verdict: changes

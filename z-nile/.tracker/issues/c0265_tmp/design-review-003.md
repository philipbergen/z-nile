# Review 003: f0265 (design mode)
Inputs: prep head b52c965c2aadba39b92e853bf424c3ae99d7aa1f (`tracker: prep f0265 answer review round 2 (flatline, refuse, accept applied)`), origin/main f88d903d; f0265.md, check.sh, acceptance/{heartbeat,beat,lost,dispatch}.spec.luau, experiments/heartbeat.proto.luau, design-review-001/002.md, design-refute-001/002.md, harvest.md and the four new lessons; `./zn capture f0265` (capture 5208b315, a real `tracker: new` commit, no marker); `git show origin/capture-workers:z-nile/.tracker/issues/c0265/c0265.md` and `git diff --stat origin/main...origin/capture-workers` (read only, not merged); the prototype copied to `z-nile/engine/heartbeat.luau` and the four specs replayed with `../zn run --time 300 -- lune run tests/run -- …` (heartbeat 15/15 pass; beat 1/9, lost 1/11, dispatch 1/2, each failing on an assertion or a missing command, not on setup), `./zn promote-check f0265` with it in place (OK), copy deleted, `git status` clean; z-nile/engine/main.luau (claimFile, rememberClaim, rememberedClaim, setStatus, cmd.status, fold, release, sync, worktree, READ_ONLY), engine/publish.luau (commit's attempt loop), engine/runner.luau, tests/lib/{fakecli,trackerfix,fixture,fence}.luau, lib/fence.sh, lib/git-hooks/{pre-push,reference-transaction}, z-nile/check.sh; c0053/commands-prep.spec; `gh pr list --state open` (through `./zn run`); zz-review, zz-rules, zz-arch, zz-test, z-design skills; `./zn lessons --when design --full`.
Dropped from design-review-002: F10 (the refute is right: a stamp collision cannot be forced in a fixture). Verified fixed in the documents: F1 (main never autobeats, entry dropped on a changed stamp, docs corrected), F2, F4, F7 (bound, throttle advanced on failure, hung-remote case), F8, F9 (promote-check OK with the prototype), F11, F12. F3, F5 and F6 are answered in part; what is left is reported below with new evidence.

I walked beat.spec and lost.spec case by case against the Design (which checkout runs each command, each entry's epoch and stamp, each beat's epoch, which claims are stale, what `plan` deletes). For a correct implementation of the stated design every case passes, and each listed mutant fails. The order holds: main never reads entries, wt's entries stay at T0 until its failed attempt at LATE+5400, c0020 stays parked through its PR, and the `sync` in wt at LATE+8100 drops c0010's and R0020's entries and beats c0020. dispatch.spec also holds: the step runs in the dispatcher's worktree `prep-claimed`, and the tick beats from the main checkout. The two highs come from the existing engine, which the specs never reach. The carried-move refusal turns a promoted spec red. And the automatic beat fires inside check.sh files and the gate, where the fence lets a fetch and a network push through.

### F1 [high] "The stamp this checkout remembers" is never written for a raft claimed with `status <R-id> preparing`: the refusal turns c0053/commands-prep red (not in Overrides) and refuses the taker of a rafting takeover
Where: Design, Takeover ("The carried `status <id> prepared` … refuses when the stamp on origin differs from the one this checkout remembers"); Assumptions, Q6 ("a lost rafting claim … is taken over by `status <R-id> preparing`"); Regression guard (`Overrides: none`); z-nile/engine/main.luau `setStatus` (after the publish: `if not store.isRaftId(id) then … rememberClaim(id, …)`), `fold` (`local mine = rememberedClaim(raftId)` … `fold takes a prepared raft (or one this checkout claimed)`), `release` (`… is not this checkout's: give back only your own claim (--force …)`).
Evidence:
- `setStatus` remembers only issue claims. Only `new raft`, `fold` and `recombine` write a raft's memory. A raft's `status <R-id> preparing` leaves the old memory, or none.
- c0053/commands-prep.spec runs `new raft … zraft` in `cap` at line 51, which remembers claim A. Then `status rz new` at line 54 (a published move from preparing: the claim file stays) and `status rz preparing` at line 73 (origin gets claim B, memory still A). At line 125, `trOk(cap, { "status", rz, "prepared" })` is the carried move, and it is the checkout's own re-claim. Under the Design's rule (origin B ≠ remembered A) it is refused with "taken over", so the promoted case turns red. No Overrides line names it. My search for carried moves in promoted specs (`git grep -nE '"status", *"[cfR][0-9]+", *"prepared"|, "prepared" *\}' -- 'z-nile/tests/**/*.luau'`) gives 28 hits in c0053/commands-{claim,prep,start} and c0116/claims. I traced only this one; the rest need the suite run below.
- lost.spec's rafting takeover (`status R0020 preparing` in wt2) leaves wt2 with no `.cache/tracker-claim-R0020`. The replay fixture shows wt holds `tracker-claim-R0020` and wt2 has no `.cache` at all. So the taker's next `fold R0020 …` is refused, `release R0020` needs `--force`, and its own carried `status R0020 prepared` is refused by the new rule ("" ≠ origin's stamp). The design hands the taker a claim it cannot use. No case runs the taker's next step.
- The Design never says what "remembers" means when the checkout remembers nothing. That covers any prep restored with `./zn worktree … --from origin/prep-<slug>`, which is the Q6 branch handling itself, when the takeover was run in another checkout first.

Critique: the decided rule (the user's "refuse": "once the claim's stamp has changed") needs to know who changed the stamp. Comparing origin with a per-checkout memory works only if every claim path writes that memory. The tempting fix is "refuse only when a memory exists and differs". That still refuses commands-prep's own re-claim, whose memory is A.
Consequences: if every claim publish (`status <id|R-id> preparing`, the takeover included) writes the memory, a checkout's own re-claim updates it, and the old claimant keeps the stale one. Then "remembers nothing" must have a defined answer. Allowing it keeps today's flows (and a checkout that lost its `.cache` passes); refusing it breaks every prep without a memory on landing day. Q6's branch handling must also say the taker claims from inside the worktree it will work in.
Recommendation:
- `setStatus` writes `rememberClaim` for raft claims too, so every `status <id|R-id> preparing` publish (and every takeover) records the new stamp in the checkout that made it.
- Refuse the carried move only when this checkout remembers a stamp and it differs from origin's. Say in the Design that a checkout with no memory passes, and why.
- Make the skills' takeover order (Q6) "create or enter the worktree, then `status <id> preparing` there".
- Cases: (1) commands-prep's flow (`new raft`, `status R new`, `status R preparing`, carried `prepared`) passes; (2) after lost.spec's issue takeover, wt2's carried `status c0010 prepared` passes; (3) after the rafting takeover, wt2's `release R0020` passes without `--force` (or its carried move passes); (4) the old claimant is still refused.
- Run the whole z-nile suite on a prototype of the rule before naming Overrides (z-design/confirm-overrides-with-a-suite-run).
Lesson: z-design/confirm-overrides-with-a-suite-run

### F2 [high] The automatic beat fires inside checks: a nested `./zn lessons`, `./zn check` or the gate's `./zn skills --check` in a raft worktree fetches and pushes a ref to the real origin, and the fence lets it
Where: Design, Automatic beats ("Every `./zn` command except `beat`, `run`, `reap` and `READ_ONLY` ones first reads the worktree's entries … it beats that item"); AGENTS.md ("No check may ever change the real repository"); z-nile/lib/git-hooks/pre-push (`chain "$@" # a network remote, from a check.sh flow`); z-nile/lib/git-hooks/reference-transaction ("A check.sh flow (not a spec run …) may still fetch").
Evidence:
- `git grep -nE '(ZN_ROOT|\$R|\.\./\.\.)/zn"? (lessons|skills|capture|spend|status|check|sync)' -- '*/check.sh' ':!*/done/*'` hits pickman/.tracker/issues/d0149/check.sh:19 (`"$ZN_ROOT/zn" check f0126 && …`), c0136/check.sh:53 and 55, c0181/check.sh:26, 88 and 90, c0193/check.sh:29, R0072/check.sh:17 and 20, and R0068/check.sh:16 (`lessons --check`, `--uncovered`, `--codified`, `--consolidate`). None of these commands is exempt. z-nile/check.sh:213 runs `./zn skills --check` in the gate.
- `$ZN_ROOT` is the raft worktree. Once the executor beats from it, that worktree holds `.cache/tracker-beats/<R-id>`. Any of those checks that runs 300 s or more after the last beat does the full autobeat: fetch, `ls-remote`, `git grep`, and `git push origin <sha>:refs/zn/hb/…`.
- In a check.sh flow (ac.sh's fence, not a spec run), pre-push lets a network remote through, and reference-transaction lets a fetch move `refs/remotes/*`. So the push reaches the real GitHub origin from inside a check. In a spec run the push is refused and fails with a warning on stderr. Either way, whether a check writes to the remote and prints a warning depends on the wall clock. c0137's check.sh line 21 expects checks to "pass silently".

Critique: review item 9. This is a path from checks to the real repository (its origin and its `refs/remotes`) that the runner cannot see and the Design does not mention. The tempting fix is to turn the autobeat off whenever `PICKMAN_FENCE_SPECS` is set. But beat.spec and lost.spec need it on inside spec runs, for their fixtures.
Consequences: the switch must tell a fixture checkout from the real one, which the fence already does (`PICKMAN_FENCE_REAL_GIT` lists the real git directories in every fenced run, check.sh flows included). The heartbeat then stays the job of the `./zn` process the agent started (the outer `./zn check`, the loop, the dispatcher). F7's beat during long commands has to come from that outer process too.
Recommendation:
- The automatic beat, and any heartbeat network call a command makes on its own, is skipped when the command's git common directory is one that `PICKMAN_FENCE_REAL_GIT` lists, or when the process runs under a check or spec fence for this checkout. Put the decision in one pure function (`heartbeat.autoAllowed(env, commonDir)`) with cases: a fixture under `.cache` is on, the real repository is off, and no fence is on.
- Add a Rules row (mutant: the autobeat ignores the fence).
- Add a fixture case: a check.sh in the fixture that runs a nested `./zn lessons --check` with a fake `PICKMAN_FENCE_REAL_GIT` naming the fixture's own git directory writes no beat.
- State in the zz-test skill's "Caught only by review" list that a nested `./zn` in a check never beats.

### F3 [medium] A malformed beat ref makes `lost` list a claim as lost while every takeover of it is refused, and nothing ever removes the ref; AC3's label says the opposite of the spec
Where: Design, `./zn lost` ("A malformed beat ref is named on stderr … and the rest still judged"); Takeover ("`; no heartbeat verdict: <reason>` when anything was unreadable or malformed"); check.sh AC3 ("… malformed beat refs and a hung remote make nothing lost and refuse a takeover"); lost.spec:253-260; heartbeat.plan (deletes only parsed beats).
Evidence:
- With `refs/zn/hb/garbage` on origin, lost.spec:257-258 expects `lost` to list c0010 (lost), and lines 254-256 expect the takeover of the same claim to be refused. An agent that follows "take lost work first" is sent to an item it cannot take.
- AC3's label says malformed refs "make nothing lost", and the spec asserts c0010 is listed. The label and the command disagree (z-design/spec-design-correspondence).
- `plan` deletes only refs that `parse` returned as beats. A malformed ref stays until someone deletes it by hand, so one stray ref (a probe, a ref from a newer format, a typo) blocks every takeover in the tracker. The refusal names the ref but not the command that clears it.

Critique: zz-arch/refusals-are-gate-checks: a refusal that blocks every caller needs its recovery written where it fires.
Consequences: making `lost` report unknown (`[stale?]`, no lost lines) whenever a malformed ref exists matches rule 7 and the takeover. But then one stray ref blinds `lost` for everyone, so the recovery becomes mandatory.
Recommendation: pick one reading for the user's "unknown is never lost". Either a malformed ref marks every stale claim `stale?` in `lost` and `status` (and refuses takeovers), or only a malformed ref that names the claim's stamp (`refs/zn/hb/<stamp>/…`) does. Name the recovery in both messages (`git push origin :<ref>`), fix AC3's label to match, and make lost.spec:257-259 follow the choice.

### F4 [medium] `questions.md` parks a claim only where `lost` and `status` run in the main checkout; the takeover, which always runs in a worktree, is unpinned
Where: Design, Parked ("… `.cache/dispatch/<id>/questions.md` exists in the main checkout"); lost.spec:154-159; main.luau cmd.status (`refuseInMainCheckout("status")` for every move).
Evidence: the only questions.md case writes `{h.f.main}/.cache/dispatch/c0010/questions.md` and runs `status` and `lost` with `cwd = h.f.main`, so a mutant that reads `.cache/dispatch` relative to the current checkout passes. Every takeover runs in a worktree, because a move is refused in the main checkout. Under that mutant a dispatched prep waiting on the user's answer, with no PR yet (decision (a)'s case), is taken over from any worktree once it is 15 minutes stale.
Critique: zz-test/pin-fail-safes-where-they-act: a parking rule is applied at each reader (list, `lost`, takeover), so it is pinned at each.
Consequences: none beyond the case.
Recommendation: add a case where the questions.md sits in `h.f.main` and the takeover runs in wt2 (`status c0010 preparing`, refused with "parked"). Name the rule "read from the main checkout (`mainRoot()`), wherever the command runs" in the Design and in its row.
Lesson: zz-test/pin-fail-safes-where-they-act

### F5 [medium] The takeover's re-check at publish has no edge case, and the row's reason ("cannot be forced in a blocking fixture") is false (repeat of design-review-002 F5)
Where: Rules and mutants, "the takeover re-checks the stamp at publish | (pure canTakeOver) | … reasoned"; Design, Takeover.
Evidence: `publish.commit` fetches and re-runs its callback on every attempt (publish.luau:343, `for attempt = 1, max do … fetch …`). lost.spec already replaces `git` on PATH with a shim. A shim branch that, on the takeover's first `push … main` while a marker file exists, first pushes a restamp of c0010 from `h.f.other` makes that push fail, and the retry runs the callback on the new stamp. The race is forced without blocking. The pure case kills a wrong `canTakeOver`, but not a call site that passes `judgedStamp` for both arguments or checks before `publish.commit`. Review 002 F5 recommended this edge case.
Critique: z-design/reasoned-rows-claim-testable-reasons and zz-test/kill-mutants-where-the-value-is-built.
Consequences: the shim must answer only that one push, by the marker (zz-test/stand-ins-answer-only-named-arguments).
Recommendation: add the case (wt2's takeover meets a stamp changed between verdict and push, is refused naming the new stamp, and origin keeps the other terminal's stamp), and mark the row `run` once it has failed for the "verdict alone decides" mutant on a prototype.
Lesson: z-design/reasoned-rows-claim-testable-reasons

### F6 [medium] `--watch`'s restamp stop and its retry after a failed tick have no edge case, and "the loop has no failure branch" is not something the code guarantees (repeat of design-review-002 F3)
Where: Design, `./zn beat <id> [--watch]` ("a failed beat is said on stderr and retried at the next tick (the loop has no failure branch)"); Rules row "`--watch` stops on a changed stamp or before its bound … run (pure)"; beat.spec:187-205.
Evidence:
- The engine's git calls raise on failure (`sh.git`, `fail`), so a tick that calls the ordinary beat path without a `pcall` exits 1 on the first failed push. Retrying is code someone has to write, so there is a branch to test.
- `heartbeat.watch` decides the stop, but an edge mutant that reads origin's stamp once at start (no fetch per tick) never sees a restamp, and passes every case.
- The row's "loop that never beats" is an edge mutant, not a pure one, though the row is marked `run (pure)`.

Critique: z-design/spec-design-correspondence.
Consequences: with `ZN_BEAT_EVERY=1` both cases take a few real seconds. That fits beat.spec's existing six-second case.
Recommendation: add two cases under `ZN_BOUNDED_DEADLINE = started + 8`. (1) A shim makes the first push fail: stderr names it, the exit is 0, and a later real-clock beat of c0010 exists. (2) `h.f.other` restamps c0010 after the first tick: `--watch` exits 0 before the deadline, says why, and writes no beat of either stamp after the restamp. Give each its own row.

### F7 [medium] A command that runs longer than the stale limit beats only when it starts: after the loop's hour, `./zn done` or a full gate reads lost mid-run and is offered first
Where: Design, Automatic beats ("first reads the worktree's entries … beats that item"); The skills ("when it reports its bound, restart it, or rely on the automatic beat"); Problem ("An agent working an item pushes a heartbeat every 5 minutes").
Evidence: the autobeat runs once, before the command. A lead whose `--watch` hour has ended and who follows the skill's "rely on the automatic beat" then runs `./zn done R0010` (the full gate) or `z-nile/check.sh --full`. When that takes longer than 900 s, the raft is stale and, with no PR yet, lost. Another worker's `./zn lost` lists it first, and `/z-run` re-adopts an active raft (as today). The agent is working and has not beaten for 15 minutes, which the Problem says should not happen. The rewritten capture on origin/capture-workers asks for "a beat … into long `./zn` commands".
Critique: the "or" in the skill bullet makes the unsafe path the instructed one. The tempting fix is to delete "or rely on the automatic beat". But an interactive lead that doesn't restart the loop then has nothing to beat during its long commands.
Consequences: a beat from inside a long command must come from the outer `./zn` process. A nested `./zn` inside the check it runs must not beat (F2).
Recommendation: `check`, `done`, `land` and the gate start a background tick (the dispatcher's tick, reused) while they run, in a worktree that holds an entry. Add a case: `./zn check <id>` whose check.sh sleeps three seconds under `ZN_BEAT_EVERY=1` leaves a beat dated during the run. Give it a row.

### F8 [medium] The capture rewrite on `origin/capture-workers` is a rename of this item (f0265 → c0265, now a chore) with a new Problem, not only a wording note: escalate to the user
Where: Assumptions, "Capture wording, for the user"; harvest.md (the note on c0265); check.sh AC5 (`grep -qE "^\| .* \| f0265 \| exists \|"`).
Evidence: `git diff --stat origin/main...origin/capture-workers` (commit 2e282833, `tracker: new c0260 … c0265 …`) shows `{f0265/f0265.md => c0265/c0265.md}` and `{f0265 => c0265}/check.sh`. It is the same item (status `new-marble-copper-copper`). Its Problem quotes the user and adds outcomes this design does not take on:
- "the takeover is recorded (c0263)";
- "a beat built into z-work's loop (c0253) and into long `./zn` commands";
- "even if a human started it without updating the rank".

The design notes only "pushed to main". Whichever lands second meets a rename/modify conflict on this folder: this prep rewrites f0265.md and check.sh, and capture-workers renames both with edits. If c0265 lands, AC5's roadmap row, the promoted folder `tests/acceptance/f0265` and every `f0265` in the documents name an id that no longer exists.
Critique: z-design/design-the-execution-window ("captured new work on the same modules, and has the user ruled on how the two fit?") and z-design/never-narrow-captured-scope: the confirmed capture is 5208b315, but the user is rewriting it.
Consequences: if c0265 becomes the capture, its added outcomes need a Design and criteria here, or a `Scope decision` line handing them to c0263 and c0253.
Recommendation: escalate to the user, with these options and their costs:
- (a) land this prep as f0265 first, then the capture branch is rebased so the rename carries this folder (costs a rebase of capture-workers, and c0265's added outcomes need a decision line);
- (b) land capture-workers first, then this prep moves to c0265 (all ids and AC5 change, and the design takes c0265's outcomes or records `Scope decision` lines);
- (c) the user withdraws the rename.

Record the answer as a `Decided with the user` line before the prep lands.
Lesson: z-design/design-the-execution-window

### F9 [low] Text left from the earlier readings contradicts the decisions
Where: Unknowns & experiments, "Lessons pass" ("`new-rules-migrate-existing-work` (day one: beatless claims are never lost, so no claim flips on landing)"); U2 ("clock skew beyond 600 s mislabels (Q7, pending)"); Test plan, lost.spec ("ZN_NOW outside checks", a case removed in round 2).
Evidence: the user's "flatline" makes every beatless claim older than 900 s lost on landing day (Assumptions, Implementation step 1), and Q7 is decided ("accept").
Critique: z-design/restated-rules-move-together.
Consequences: none.
Recommendation: rewrite the three sentences to match the decisions, and search the document for "never lost", "heartless" and "pending" before the next round.
Lesson: z-design/restated-rules-move-together

### F10 [low] The old claimant's case checks only the taker's stamp, and the old claimant is never told its claim was taken
Where: lost.spec:298-303; Design, Automatic beats ("the entry is deleted and nothing is beaten").
Evidence: the loop asserts only that no ref equals `refs/zn/hb/<taker's stamp>/<at + 2·STALE>`. A worktree that keeps beating its own old stamp passes, and so does one that never deletes the entry. Review 002 F1 asked for "no beat for either stamp, and the throttle entry is gone". When the entry is dropped the old claimant prints nothing, so it can keep working for hours until its carried move is refused.
Critique: a returning agent (a laptop that slept 20 minutes) is the common case of a takeover.
Consequences: none.
Recommendation: assert no new ref of either stamp and that `{wt}/.cache/tracker-beats/c0010` is gone. Print once on stderr when an entry is dropped for a changed stamp (`c0010's claim was taken over (now <stamp>): stop working it`), with a case.

### F11 [low] "Killed after `ZN_NET_SECONDS`" names no mechanism, and killing only the git process leaves its child holding the pipe
Where: Design, Automatic beats ("Each heartbeat call … is killed after `ZN_NET_SECONDS`").
Evidence: lost.spec's shim `sleep 30` is a child of the shim's `sh`, as `ssh` is a child of `git ls-remote` on a real hung remote. Killing the process the engine started (an `alarm` wrapper, say) leaves that child holding stdout, so Lune's `process.exec` waits for it anyway. The spec catches this (line 211), but an executor will reach for the obvious wrapper first. engine/runner.luau:47-49 already starts children in their own process group (`setpgrp`).
Critique: zz-arch/children-need-a-lifeline.
Consequences: none.
Recommendation: say "run in its own process group and kill the group", and point at runner.luau's helper.

### F12 [low] The twin of `heartbeat.clock` for `ZN_BEAT_EVERY` and `ZN_NET_SECONDS` has no signature, case or row
Where: Design, `ZN_NOW, ZN_BEAT_EVERY, ZN_NET_SECONDS` ("decided by the pure `heartbeat.clock` and its twin for the other two"); the signature list; heartbeat.spec.
Evidence: only `clock` is listed and tested. A mutant that honours `ZN_BEAT_EVERY=1` outside a spec run passes every spec. In production that loop would beat every second, and a short `ZN_NET_SECONDS` would turn every heartbeat call unreadable.
Critique: the user's "accept" covers both variables ("honoured only inside spec runs").
Consequences: none.
Recommendation: name it (`heartbeat.setting(env, name, default)`), add the pure cases (marker absent, `1`, non-numeric) and a row.

### F13 [low] The first beats of `fold`, `recombine` and `start` are `reasoned` as "same hook as `new raft`", which is not a reason a mutant can't be seen (repeat of design-review-002 F6, in part)
Where: Rules and mutants (no row for these three); design-refute-002 F6.
Evidence: each command publishes through its own call site (fold's `publish.commit` in `cmd.fold`), so leaving the hook out of one is a separate mutant. beat.spec could seed a second prepared backlog raft and a prepared, raftless issue with `design: ready` and run `fold` in wt.
Critique: z-design/reasoned-rows-claim-testable-reasons.
Consequences: none.
Recommendation: add the `fold` case and row. Keep `recombine` and `start` `reasoned` only with a reason about their fixtures.

## Candidate lessons (for the lead)
- zz-arch: **an effect added to "every command" names every process that runs those commands (check.sh files, the gate, specs, the dispatcher) and says whether it fires there**, because f0265 review 003 F2 found the automatic beat would push to the real origin from nested `./zn lessons` calls in check.sh files, which the fence allows. Check: which check.sh, gate step or spec runs this command in the real checkout, and what does the new effect do there?
- z-design: **a rule keyed on "the claim this checkout remembers" lists every path that makes a claim and whether it writes the memory**, because f0265 review 003 F1 found `status <R-id> preparing` never writes it, so the new refusal broke a checkout's own re-claim and the rafting taker. Check: for each command that publishes a claim stamp, does it update this checkout's memory, and what does the rule answer when there is none?

Verdict: changes

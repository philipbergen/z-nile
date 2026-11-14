# Review 013: c0265 (design mode)
Inputs: prep head a79f8eb8 (`tracker: prep c0265 E5 wording`). This is round 2 of the restarted count (the heartbeat-branch design). I read c0265.md, check.sh, acceptance/{heartbeat,beat,lost,edge}.spec.luau, proofs/{dispatch,race}.spec.luau, experiments/heartbeat.proto.luau, harvest.md, design-review-012.md, design-refute-012.md and `git diff 62c8b64e..HEAD`. In the engine I read `main.luau` (READ_ONLY, `claimFile`/`rememberClaim`, `setStatus`'s carried `stamp(to)`, `stop`'s subjects at 4785/4853) and `status.carriedByPr`. I also read the lessons `liveness-names-held-not-worked-states` and `automatic-effects-have-an-end-and-a-subject-check`, and ran `./zn lessons --when design --full`.
Capture: `./zn capture c0265` prints `(no capture commit: first add)`, the user's #258 rename, so it is not a confirmed capture. I judged it from that commit. The title, the Problem and the Solution are unchanged apart from added `Decided with the user` lines and one Solution bullet of design detail. Every captured outcome has a Design and a criterion.
Round 1 (review 012) as answered in the documents:
- answered: F4 (one lease rule in `plan(…, remembered)`, the create-only re-read, an edge case armed on the hb read), F7 in part, F8, F9 and F10.
- answered for preparing claims only: F1 (the stamp-bound beat). F2 is answered by stop then ready. The holes are F1 and F4 below.
- answered in part: F3 (`ready`'s drop has no mechanism, F7 below), F5 (the answer breaks the pinned proof, F3 below) and F6 (F8 below).
Replays (from z-nile, with the prototype copied to `engine/heartbeat.luau` and deleted after; `git status --short` is empty):
- `../zn run --time 900 -- lune run tests/run -- <spec>`: heartbeat 20/20.
- Against the unchanged engine, beat, lost, edge, dispatch and race each pass their setup case and fail every other case on the missing `beat`/`lost` (the red state E7 describes).
- `./zn promote-check c0265`: OK.
- Mutant "the lease is always the sha seen" (`remembered` ignored in `plan`): heartbeat.spec fails one case, the lease case.
- The proof hashes match `git hash-object` (`6fd10bdf…`, `5ae72235…`). `bash -n check.sh` is clean.

Walk (a correct implementation of the design as stated):
- heartbeat.spec passes.
- beat.spec passes until the last case, which fails (F1).
- lost.spec passes until the last case, which fails at line 522 (F2). Checked along the way:
  - the old claimant's bare `beat` and its restarted `--watch` exit 1 before any tick, so the taker's tip is unchanged;
  - `sync` says both "taken over" lines;
  - the give-back deletes hb/<c0070 stamp>, and wt2's next command says "claim ended";
  - the takeover deletes hb/<old> and creates hb/<new>.
- edge.spec passes (with the weakness in F9).
- proofs/dispatch passes.
- proofs/race fails its first case (F3). The restamp, long-check and hung-remote cases pass.

### F1 [high] beat.spec's last case fails for the stated `--adopt`: the main checkout gains a claim memory, so its bare `beat` no longer refuses
Where: The lease and ownership ("`--adopt` is the stated adoption: it beats origin's stamp and writes the memory"; "A checkout with no memory (the main checkout, a fresh clone) refuses a bare `beat <id>`"); beat.spec cases "beat pushes a branch from the main checkout too" (T0+300, T0+600), "a beat keeps another terminal's fresh beat" (T0+1200) and "a checkout that does not hold the claim refuses a bare beat" (T0+1500).
Evidence:
- Three earlier cases run `beat c0010 --adopt` in `h.f.main`. As written, each writes `h.f.main/.cache/tracker-stamp-c0010` holding c0010's stamp. The memory is cwd-relative, like `claimFile`.
- The last case then runs a bare `beat c0010` in the same main checkout. Its memory equals origin's stamp, so by the rule it beats and exits 0.
- The spec expects `ok == false` and "does not hold", so the case fails.
- The other reading ("the main checkout has no memory") passes, but the Design never says `--adopt` skips the memory there. The dispatcher's `--adopt --stamp` runs in the main checkout too, so on the literal reading it writes one memory file per dispatched item, and nothing ever removes them.
- The lesson's check asks: "can the main checkout ever hold one?" The Design answers it for the throttle entry but not for the memory.

Critique: the Design states the rule two ways and the spec pins only one of them. An executor who follows "writes the memory" cannot pass a sequestered case, which is a stop condition.
Consequences: "the main checkout never writes or reads a claim memory; `--adopt` there is per call". Then:
- every beat from the main checkout must say `--adopt`. The specs already do, and so does the dispatcher.
- `ready` must not write one. It doesn't today: it is not in the Design's list of claim publishes.
- AGENTS.md's list of files `./zn` writes in the main checkout stays as it is.

The opposite rule (write it everywhere) would need the spec changed instead, and would make the main checkout hold a stale memory per item forever.
Recommendation: state in The lease and ownership and in Automatic beats that the main checkout never writes or reads `.cache/tracker-stamp-<id>`, and that `--adopt` there beats for that call only. Add one row with the mutant "`--adopt` writes the memory in the main checkout", killed by beat.spec's last case.
Lesson: zz-arch/automatic-effects-have-an-end-and-a-subject-check

### F2 [high] lost.spec's stop-then-ready case cannot pass: the pull request list still names R0010, so R0010 is parked, not lost
Where: lost.spec, case "a pull request naming only the raft parks the raft…" (line 210 writes `prs.json` with `"R0010: lost raft"`), and the last case, "a lost readied raft is taken over by stop and ready" (line 522: `t.expect(has(zn(h.f.main, { "lost" }, at).stdout, "R0010 active")).toBe(true)`).
Evidence:
- `prs.json` is written only at lines 174 and 210 and never reset. The `ghfail` markers are removed after each use.
- At `LATE + 14 * STALE` the fake `gh pr list` therefore still returns the "R0010: lost raft" PR.
- `parkedBy` matches R0010 by whole id, so `settle` makes R0010 `parked`, and `lost` prints no R0010 line.
- A correct implementation therefore fails line 522. The stop and ready that follow would pass, since `stop` is open to anyone.

Critique: the case is new this round, and the edge is not prototyped, so nothing ran it. Its precondition was set by an earlier case.
Consequences: resetting the list makes c0020 lost too, which does not matter to this case. Keeping the c0020 PR keeps every earlier assertion's world.
Recommendation: before the `lost` call in the last case, write `prs.json` as `[{"title":"tracker: prep c0020","headRefName":"p"}]`, or `[]`. Walk every later case against the PR list it inherits.
Lesson: z-design/prove-specs-pass-on-a-prototype

### F3 [high] (repeat of review-012 F5) Under the "no classification" answer, the pinned race proof's failed tick is never reported, so a correct implementation fails AC5
Where: The lease and ownership ("any failed write is followed by a re-read and `heartbeat.rejected` (retry on the sha there, create, or lost); a second failure is a failed tick whose message relays git's stderr"); `--watch` ("a failed tick relays git's stderr"); proofs/race.spec "beat --watch says a failed tick and keeps beating" (the shim's `pushfail` fails one push and removes its marker; `has(r.stderr, "fake beat push failure")`).
Evidence:
1. The first tick's push fails once with `fatal: fake beat push failure`.
2. Per the Design, the beat re-reads, and `rejected(stamp, stamp, beats)` returns `retry` on the sha there, which is still the branch the beat remembered.
3. The retry succeeds, because the marker is gone. No second failure happens, so no failed tick happens and nothing is relayed.
4. `r.stderr` lacks the message, and the pinned proof fails.

Review 012 F5 named exactly this outcome ("an implementation treats every failed push as a rejection … the message may never be relayed"). The answer made it the stated design.
Critique: the proof needs either a relay of the first failure or a shim that fails twice. A first-failure relay would also print on every co-beater conflict (the dispatcher's beat against the agent's remembered sha), which is noise on most beats of a dispatched step.
Consequences:
- Changing the proof moves its pinned hash in AC5 (allowed in prep).
- A "relay every failure" rule needs a case showing that a co-beater rejection followed by a successful retry is silent. Otherwise the noise is unpinned.
Recommendation: keep "a second failure is a failed tick". Change the race shim to fail the push and its retry (for example `pushfail` holding a count of 2, decremented per push), and re-pin. Add a second arm in which a single failure is followed by a successful retry: the tick lands and stderr is silent. Add both to the Rules table.

### F4 [high] A lost `active` raft's old owner is not told when it comes back by its loop restart: the raft worktree can beat only through an unbound `--adopt`, which adopts the taker's stamp
Where: The lease and ownership ("`--adopt` … beats origin's stamp and writes the memory"); Takeover ("Every claim publish (`status …`, `new raft`, `fold`, `unfold`, `recombine`) records the new stamp", which leaves out `ready`); Automatic beats ("`/z-run` re-adopts it (its worktree writes the entry)"); The skills (z-design: "a restart elsewhere needs `--adopt`"; z-run: "the same loop for the raft"); Problem, `Decided with the user (2026-11-08)` ("this would tell the process that it lost the ownership if it comes back around"); AC3 ("a restarted loop … never adopt[s] the taker's claim").
Evidence:
- `ready` runs in the main checkout, which writes no entry and is not on the memory list. z-run then works in `cd "$(./zn worktree <R>)"` (z-run SKILL step 3), where no claim publish happens.
- So a raft worktree has no memory and no entry. Its bare `beat R0010 --watch` refuses ("not held by this checkout (use --adopt …)"), and the autobeat has nothing to beat. The only way z-run's loop can run is `beat R0010 --adopt --watch`, which writes memory S1.
- The raft goes lost, and someone runs stop then ready (stamp S2). The old session comes back, its loop reports its bound or was killed, and it restarts the command its skill gave it, `--adopt`.
- `--adopt` beats origin's stamp, S2, rewrites the memory to S2 and is never told. From then on its autobeat matches origin too.
- The same happens to a prep agent that restarts "elsewhere" as z-design prescribes.
- lost.spec pins the restart refusal only for a preparing claim from a worktree whose memory came from `status … preparing`. Nothing covers the active path or `--adopt` from a checkout that remembers another stamp.

Critique: F1 of review 012 is fixed for the paths that have a claim publish and reopened for every path that needs `--adopt`. The mechanism question: an adoption is a lease renewal, and its id must come from the holder's own record, never from origin.
Consequences:
- `--adopt` must refuse ("taken over (now S2)") when this checkout remembers a different stamp. Only a checkout with no memory may adopt.
- Every adoption the skills prescribe must carry the stamp the agent was given: `--adopt --stamp <S>`. A readied raft gets S from `ready`, which writes the active stamp into `prompt.md` and rewrites it on a re-ready. A prep's S is the one its claim printed.
- z-run's first step becomes `./zn beat <R> --adopt --stamp <prompt's stamp>`, which writes the memory and the entry. The old session, holding the old prompt, is then refused.
- AC6 should grep `--adopt --stamp` in z-run.
Recommendation: state all four rules. Cases:
- lost.spec, after the stop then ready: a worktree that adopted the old active stamp runs `beat R0010 --adopt`, then `--adopt --stamp <old>`, then `--watch`. Each is refused with "taken over", and the new stamp's tip is unchanged.
- beat.spec: a worktree with memory S1 refuses `--adopt` when origin shows S2.

Rows: "`--adopt` adopts over a remembered stamp" and "z-run adopts origin's stamp, not the prompt's".
Lesson: zz-arch/automatic-effects-have-an-end-and-a-subject-check

### F5 [medium] The dispatcher's `--stamp <S>` has no S for a step that makes the claim (a z-design of a new item, a z-raft), so most dispatched steps are never beaten, and its mutant row names cases that never run the dispatcher
Where: The dispatcher ("`<S>` is the stamp `main` showed when the step started; a mismatch means the claim was taken over mid-step … A refusal (no claim yet) is ignored"); Rules row "a beat is bound to the stamp its holder owns …" (mutant "the dispatcher beating whatever holds the item", cases beat :: … and lost :: …); proofs/dispatch.spec (c0050 is claimed by the fixture before the step).
Evidence:
- A dispatched z-design of a `new` item claims inside the step. At step start main shows no stamp, so S is nil.
- Either every later tick is "a mismatch", so the dispatcher stops and says the claim was taken over, or it passes nothing and the bare form refuses. Either way the step's claim gets no dispatcher beat for the whole step.
- Under `ZN_DISPATCH=1` the step runs no loop. Its only beats are the agent's `./zn` commands, so a 15-minute think reads lost, and a lost-first worker takes it over.
- No case runs the dispatcher on a restamp, and none on a claim made mid-step. The row's dispatcher mutant cannot be killed by the cases it names.

Critique: the "no claim yet" refusal shows the intent (keep trying), but S fixed at step start makes it impossible. The tempting fix, "S is the first stamp seen", adopts a foreign worker's claim made during the step.
Consequences: the step's agent claims in its worktree (`st.worktree`, which the dispatcher knows), and that claim writes `.cache/tracker-stamp-<id>` there. The dispatcher should read S from that memory on each tick: absent means not yet claimed (skip quietly), present means fixed thereafter. A later difference from origin means taken over: stop, and say so once.
Recommendation: state that rule. Add a proof arm in dispatch.spec where the fake step claims a `new` item mid-step, and assert that a beat of the step's stamp arrives after the claim. Add a second arm where the item is restamped mid-step, and assert that no beat for the new stamp is written. Re-pin AC4, and move the row's dispatcher mutant onto those arms.
Lesson: z-design/results-land-on-every-path

### F6 [medium] The takeover of an `active` claim is neither recorded as a takeover nor guarded by a lost verdict, and the old lead's carried `done` is not refused
Where: The lease and ownership (stop then ready; "`stop` records the lost stamp in its commit subject (`tracker: stop R0010 (claim <stamp>)`)"); Problem ("the takeover is recorded (c0263)"); `Decided with the user (2026-11-07)` "refuse"; lost.spec's last case.
Evidence:
- Every `stop` now writes `(claim <stamp>)`, whether it aborts a live raft or takes over a lost one. `ready` writes its normal subject. A provenance reader (c0263 reads git) cannot tell a takeover from an abort.
- `stop` checks no verdict. A live or parked raft is "taken over" by the same two commands, and only the skill sentence "a parked one is left alone" stops it. A preparing takeover, by contrast, needs an explicit lost verdict.
- The old lead's `./zn done` in its old worktree is told once on stderr (its entry), but nothing refuses it. Its carried `prepared` analogue would be refused (the user's "refuse").

Critique: the capture's "recorded" outcome and the parity with the preparing path are both thinner for active claims.
Consequences: a lost-aware `stop` reads the verdicts. It already reads the beats to drop the branch, so the only added cost is the lazy `gh pr list`.
Recommendation:
- `stop` writes `tracker: stop R0010 (takes over <S>)` when the verdict is lost, else `(claim <S>)`, and the lost.spec case asserts the former.
- `done` (and `land`) from a worktree whose memory differs from origin refuse with the taker text, as the carried `prepared` does.
- Refusing `stop` on a live or parked raft would change who may stop a raft. Escalate to the user: keep `stop` open (today's rule) or require a lost verdict or `--force`.
- Add rows and cases for each.

### F7 [medium] `ready` cannot find the rafting claim's branch to drop, and `done`'s drop is undone by the next autobeat
Where: When the branch is deleted ("`ready` (it drops the rafting `preparing-…` branch in the same step as the first beat of the new `active-…` stamp)", "`done`"); Rules row "… (give-back, stop; ready and done reasoned)".
Evidence:
- `ready`: a raft reaches `ready` as `prepared-<words>`. The carried `status R prepared` writes `stamp(to)`, fresh words (`main.luau` setStatus, line 1435). The beat commit's subject is `hb <stamp> <epoch>`, which names no item. When `ready` runs, neither main nor the branch says which hb branch was this raft's rafting claim, so it has no input for the drop. Only history would tell (`git log -S"status: preparing-" -- <doc>`).
- `done`: for a raft it runs while the claim is still active on main, so the worktree's entry still matches origin's stamp. The next `./zn` command there (`land`, `commit`) beats again, and a create-only write recreates the branch.

Critique: these are two of the four "deleted when the task completes" paths. The row's "reasoned" hides a mechanism that is missing, not just untested.
Consequences: when the carried `prepared` merges, the rafting stamp is unclaimed, so pruning already removes its branch 15 minutes later. `done` should also drop the entry, so that no later command recreates the branch.
Recommendation: replace `ready`'s drop with "pruning removes it once unclaimed (the prep PR's merge ends it)", or give `ready` a stated history read with its cost. Make `done` drop the worktree's entry together with the branch. Add a beat.spec or lost.spec case: after `done` (or a give-back), the next command in that worktree does not recreate the branch.
Lesson: z-design/spec-design-correspondence

### F8 [medium] (repeat of review-012 F6) `Overrides: none` is still confirmed only on the claim paths
Where: E8 (re-run: c0116, c0053, c0117, tooling/ready-members, recombine-members; "`ready` and a legacy `start` were not hooked"); Regression guard; Implementation step 1.
Evidence: the E8 scratch had the memory, the carried refusal and the first beat as a branch. It did not have:
- the autobeat: every non-READ_ONLY `./zn` command in a worktree holding entries now fetches main, fetches the hb branches and may push;
- the branch drops in give-back, `stop`, `ready` and `done`;
- `stop`'s changed subject.

It was not run against the minimum set review 012 named either: c0115, c0120, c0114, c0005 and tooling/busy*. Promoted fixtures that claim in a worktree and then run more commands there, such as c0068/stop or c0117/control-cli, were never run with the autobeat.
Recommendation: add the autobeat, the drops and the stop subject to the scratch engine and run the whole z-nile suite (or at least the specs above). Record the counts and the time it adds in E8, and name any red spec in Overrides.
Lesson: z-design/confirm-overrides-with-a-suite-run

### F9 [medium] edge.spec's beat-race shim fires on any hb push, so the race it is meant to force may never meet c0071's beat, and the no-lease mutant can pass
Where: edge.spec SHIM (`*:refs/heads/hb/*)` with `racebeat` runs `takeover` for `$FAKE_ITEM`), case "a beat that races a takeover…"; Rules row "a beat racing a takeover is rejected by its lease" (mutant "a force push with no lease").
Evidence:
- The same `lessons` run in wt beats c0072 as well as c0071, since both entries are due at `os.time() + 1000`.
- If c0072's push comes first (entry order is directory order, which nothing sorts), the takeover of c0071 fires on c0072's push.
- With one fetch of main per beat (the Design's "A beat: one fetch of main …"), c0071's beat then sees the new stamp before pushing. It drops the entry with "taken over" and pushes nothing.
- Every assertion passes, but no lease was ever tested, and a no-lease force push also passes.

Recommendation: arm the takeover only on a push naming `refs/heads/hb/$FAKE_OLDSTAMP`, and assert that the race happened: the shim logs that it fired on that push and that the push was rejected. Alternatively, give c0072's entry an epoch inside the interval.
Lesson: zz-test/stand-ins-answer-only-named-arguments

### F10 [low] Small wording and edge gaps
- `--watch` on an already lost stamp must exit 1 (lost.spec), while a stamp lost mid-run exits 0 (race.spec). State that the binding check runs before the first tick and that `stop-restamped` is only for a change during the run.
- After a failed attempt the entry's sha is empty. `plan(…, remembered = "")` gives a create-only lease on an existing branch (`remembered or …`, and `""` is truthy), which costs a rejection and a retry. State that an empty sha passes `nil`.
- lost.spec expects `tracker: stop R0010 (claim <S>)` exactly, but today's raft stop subject carries the title (`tracker: stop {raft.id} {rtitle}`). Say that the title is dropped.
- The takeover's "re-reads and repeats once" has no case or row.
- Leftovers from review 012 F7: beat.spec's title "a beat is a ref outside main", and lost.spec:316 "no ls-remote".
- "In one push" in AC3 is not observable: the case sees only the end state.

### F11 [low] "A lost claim's branch is kept until its takeover" is a reading of the user's "deleted when the heartbeat drops", and it is not listed under Assumptions to veto
Where: When the branch is deleted; Assumptions to veto.
Recommendation: add it as an assumption to veto, with the alternative (delete on lost, so that the silent minutes count from landing and a returning owner recreates its branch).

Candidate lesson (for the lead; F1, F4): zz-arch, "an adoption is a lease renewal: its id comes from the adopter's record or an explicit argument, and it refuses over a different remembered id". Reason: c0265's `--adopt` beat origin's stamp, so an old owner's prescribed restart adopted the taker's claim, and the main checkout gained memories. Check: "For each path that adopts or renews a lease, where does its id come from, which checkouts may store it, and what does it do when its stored id differs from the shared state?"

Verdict: changes

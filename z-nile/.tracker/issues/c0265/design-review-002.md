# Review 002: f0265 (design mode)
Inputs: prep head 351c217a98ecddee7288db7949d3879ff83af3e3 (`tracker: prep f0265 answer review round 1 (user decisions applied)`), origin/main d1198a24; f0265.md, check.sh, acceptance/{heartbeat,beat,lost,dispatch}.spec.luau, experiments/heartbeat.proto.luau, design-review-001.md, design-refute-001.md, harvest.md and its two new lessons; `./zn capture f0265` (capture 5208b315, a real `tracker: new` commit, no marker: Problem and title unchanged, four `Decided with the user` lines added); `./zn check f0265` (0/5, the expected failures); `./zn promote-check f0265` without and with the prototype copied in; the four specs replayed with the prototype as `z-nile/engine/heartbeat.luau` (`../zn run --time 300 -- lune run tests/run -- …`; copy deleted after, `git status` clean); z-nile/engine/main.luau (READ_ONLY, setStatus, cmd.status, new raft), z-nile/tests/tooling/tracker-guarded.spec.luau, z-nile/tests/lib/fixture.luau, z-nile/lib/{fence.sh,bounded.pl,git-hooks/pre-push}, z-nile/engine/wrapper.luau; `gh pr list --state open --json title,headRefName` and `git grep` of live claims on origin/main (both through `./zn run`); zz-review, zz-rules, zz-arch, zz-test, z-design skills; `./zn lessons --when design --full`.
Dropped from design-review-001: none outright. Answered and verified: F2's own defect (c0050 now `[no beat]`), F3 (`ready R0010` now succeeds in the fixture: the replay fails at beat.spec:128, after the `must`), F4, F8, F10, F11 (every new AC5 grep has 0 hits in today's skills), F13, F15, F17. F1, F5, F6, F7, F9, F12, F14 and F16 are answered in the design but leave a hole, reported below.

The pure core is good: heartbeat.spec passes 11/11 on the prototype and its mutants are the right ones. The highs are again at the engine edge, which was not prototyped: two fixture specs cannot pass for the design as written, one case passes for a `--watch` that never beats, and two claim rules (a raft's members, two takers) give wrong answers on today's tracker shape.

### F1 [high] Automatic beats fire in any checkout that ever made a beat, the main checkout included, and `lost`/`status` beat before they judge: lost.spec cannot pass, and a dead dispatched claim is kept alive by the user's own `./zn status`
Where: Design, The engine edge, "Automatic beats" ("A beat writes `.cache/tracker-beats/<id>` … in the checkout that made it. Every `./zn` command except `beat`, `run`, `reap` and `READ_ONLY` ones first reads that folder and … beats that item"); `./zn beat` ("it changes no file … so it runs in the main checkout"); The dispatcher; Regression guard ("`READ_ONLY` stays as is"); lost.spec:139-202.
Evidence:
- `READ_ONLY` (main.luau:5989-5999) is `list audit find members metrics board workstreams promote-check stamp`, and `tooling/tracker-guarded.spec.luau:25-37` pins exactly that set. So `status` and the new `lost` are not exempt: they autobeat first.
- lost.spec, step by step under the design: case 4 runs `beat c0010` in `h.f.main` at LATE, which writes main's `.cache/tracker-beats/c0010` (`<stamp> LATE`). The next `lost` in `h.f.main` at `LATE + STALE` finds that entry `STALE` (≥ INTERVAL) old and beats c0010 at `LATE + STALE` before it judges. `lost` at `LATE + STALE + 1` then sees c0010 silent 1 s, prints nothing, and line 142 (`has(…, "c0010")` true) fails. From there on every `lost`/`status` in `h.f.main` re-beats c0010. Line 153 (`[stale?]` on c0010) fails, line 186 (`lost` still lists c0010) fails, and line 195 (the takeover) is refused as a live claim. No implementation of the stated design passes AC3.
- The same mechanism on the real tracker: the dispatcher runs in the main checkout (AGENTS.md; its run state is main's `.cache/dispatch/`), and the design names no other cwd for its `zn beat` child. `ready` runs there too. Each leaves an entry in main's `.cache/tracker-beats/`, and nothing ever removes one. Every later `./zn status`, `lost`, `sync`, `ready`, `land` or `dispatch` the user runs in main beats every item it ever beat. A dispatcher that crashed mid-step, or a readied raft nobody started, is never lost while the user keeps working.
- The entry stores `<stamp> <epoch>`, but no rule says the autobeat compares that stamp with origin's. After a takeover, the old claimant's worktree either beats the taker's new stamp (it keeps a dead taker alive) or its behaviour is undefined.
- Contradictions this leaves in the documents. `./zn beat` "changes no file", and the zz-rules main-checkout bullet says "`beat` writes a ref under `refs/zn/hb/` only", yet a beat writes `.cache/tracker-beats/<id>` in the main checkout. AGENTS.md's list of what `./zn` writes in the main checkout (prompt.md, board.html, `.cache/dispatch/`) is not in Touched modules. The Assumptions bullet says "any `./zn` command in its worktree gives it its first beat" for a claim never beaten, but a pre-existing claim's worktree has no `.cache/tracker-beats/` entry, so nothing beats it (Implementation step 1 repeats the claim).

Critique: round 1's F2 (prove-specs-pass-on-a-prototype) recommended running lost.spec against a prototype of the `lost`/`status` edge. The Mutation check says the edge was not prototyped and E7 shows only that the cases *fail* today. A fixture spec that was never seen passing has again turned out unpassable, so the mechanism to question is that: the edge specs need a prototype run. The tempting fix is to add `lost` and `status` to the exemptions. But beat.spec:132-142 uses `status c0010` in a worktree as its autobeat trigger, so the two specs would then contradict each other, and the main-checkout beater would remain through `sync`, `ready` and `dispatch`.
Consequences: an autobeat needs a fact that says "this checkout works this claim". The engine already has one: `rememberedClaim`/`.cache/tracker-claim-<id>` (main.luau:380-400; written by `status <id> preparing`, `new raft`, `fold`, `recombine`), and its value is the stamp. Keying on it brings these rules: the stamp must equal origin's or the entry is dropped (a takeover, a give-back or `done` ends the autobeat); the main checkout never autobeats (it holds no work); `ready` gives the raft its first beat but holds nothing; a raft's worktree must remember the active claim when `/z-run` enters it (or the loop's first beat must write it there), or `./zn commit` in a raft worktree beats nothing; the dispatcher beats only through its tick. A readied raft that nobody starts then reads as lost 15 minutes after `ready`. That is what decision (a) implies (no PR, no gate, no question), and `/z-run` re-adopting it is the intended pick. Round 1 F1 asked for that case, and it still has none.
Recommendation:
- Key the automatic beat on the claim the checkout remembers, with its stamp equal to origin's (the throttle epoch stays a throttle), never in the main checkout. Say how a raft worktree comes to remember its active claim.
- Correct the `beat` and zz-rules sentences ("a ref, and the throttle file in `.cache`"), and add AGENTS.md's main-checkout list to Touched modules, or state that main never gets an entry.
- Cases: (1) lost.spec as written passes, because main never autobeats; (2) after the takeover, a `./zn` command in the old worktree (`wt`) writes no beat for either stamp, and the throttle entry is gone; (3) `status` in `h.f.main` after `beat c0010` there writes no beat; (4) a readied raft unbeaten past STALE is listed by `lost`; (5) a claim seeded with a stamp and a remembered claim file (no beat) gets its first beat from a `./zn` command in its worktree, or the Assumption is reworded.
- Then prototype the edge (`beat`, the autobeat, `lost`, the `status` list and the takeover: a fraction of the 640 lines), run beat.spec and lost.spec on it, and record pass plus the listed mutants in Unknowns & experiments before the next round.
Lesson: z-design/prove-specs-pass-on-a-prototype

### F2 [high] beat.spec's "any ./zn command … beats it once an interval has passed" counts every beat on origin, including R0010's from the case before, so it cannot pass
Where: acceptance/beat.spec.luau:121-130 (`ready R0010` beats R0010's active stamp at T0) and 132-142.
Evidence: at `T0 + 1000` the worktree's autobeat writes c0010's beat and deletes c0010's older one (T0+600). R0010's beat at T0 stays: R0010 is claimed (active on origin), and only unclaimed stamps are pruned. Line 140 then expects `#beats() == 1` and gets 2. Line 141 reads `beats()[1]`, and `for-each-ref` sorts by name, so `refs/zn/hb/active-…` (R0010's, epoch T0) comes before `refs/zn/hb/preparing-…`, and the expected `T0 + 1000` is not what it reads. The same case is unpassable for any implementation that keeps a live claim's beat.
Critique: this is the defect the author's own new lesson (zz-test/background-seeds-meet-later-assertions) describes: an earlier case's item changes a later case's whole-output assertion.
Consequences: none beyond the case.
Recommendation: count and read only the beats of c0010's stamp (`stampOf("c0010", …)`), as line 91 does. Run the case on the edge prototype (F1).
Lesson: zz-test/background-seeds-meet-later-assertions

### F3 [high] The `--watch` case passes for a loop that never beats, and its refusal half depends on the caller's environment; the stamp-change exit and the retry have no case (repeat of design-review-001 F6)
Where: acceptance/beat.spec.luau:176-192; Design, `./zn beat <id> [--watch]`; Rules row "`--watch` only under `./zn run`, ends before its bound".
Evidence:
- `newest` is the maximum over every beat on origin (`has(b.stamp, "")` is always true). By then origin holds beats that earlier cases dated with `ZN_NOW`: c0010 at `T0 + 1300` (the autobeat in the `new raft` case) and the new raft's at `T0 + 1300`. `started` is the real clock, a few seconds after T0, so `newest >= started + 2` holds before `--watch` runs. A `--watch` that checks the bound and exits 0 without beating passes.
- `fixture.exec` passes `env` to `process.exec`, which adds to the inherited environment. `bounded.pl:94` exports `ZN_BOUNDED_DEADLINE` to every process of a `./zn run`. When the suite runs under `./zn run`, the way AGENTS.md asks for probes (and the way this review's replay ran), the "refused" call inherits a deadline. It is not refused, beats, and exits 0 because its next tick passes the bound, so line 178 fails for a correct implementation.
- Nothing pins "exits 0 with a message when the item's stamp on origin changed" or "a failed beat is said on stderr and retried at the next tick". Round 1 F6 recommended the restamp case.

Critique: the loop is the beat source the skills prescribe for the first hour of every interactive prep and raft, and AC2's case for it passes without it. The tempting fix is to filter by stamp. But c0010 also has the `T0 + 1300` beat, which is newer than any real-clock beat, and `plan` never deletes a newer beat, so a stamp filter alone still passes.
Consequences: with `ZN_BEAT_EVERY=1`, each beat deletes the one before, so the number of ticks shows only through the newest real-clock epoch.
Recommendation:
- Refused half: pass `ZN_BOUNDED_DEADLINE = ""` explicitly, and say in the Design that the variable must be set to a number.
- Running half: take c0010's beats with `epoch <= os.time()` and expect the newest at least `started + 2` (two ticks at least).
- Add a case: with a far deadline, `h.f.other` restamps c0010 (a `status c0010 new` or a takeover) while `--watch` runs, and `--watch` exits 0 before the deadline and says why.
- Add a case for a failed tick: an `lsfail`-style shim, a message on stderr, and a later tick that beats.
- Give each its own Rules row.
Lesson: zz-test/specs-set-host-markers-explicitly

### F4 [high] A raft parked at its PR leaves its members lost: `parkedBy` matches each claim's own `match`, and a member's holds only its own id
Where: Design, The beat (`Claim.match`: "the ids a PR may name (the item, and a raft's members)"), Parked, `./zn lost` ("a raft's members each get their own line (verdicts are per item, the raft's stamp shared)"); heartbeat.spec:118-137 (only the raft's claim carries member ids).
Evidence: `ready` stamps a raft and its members alike (on origin/main R0061, c0134, c0135 and c0137 all carry `active-pink-indigo-copper`). Today's open PRs (`gh pr list --state open --json title,headRefName`) include `R0061: c0131 header, used slugs refused, finished scans` / `R0061-z-nile-header-slug-scans` and `R0083: Project board` / `R0083-project-board`. Neither names a member. Once such a raft's lead session ends with its PR open:
- the raft is `parked`;
- each member (match `{c0134}` and so on) is `lost`, so `./zn lost` lists them first and `status` shows `[lost …]`;
- the skills send the next agent to `/z-run R0061`, a raft waiting for its human merge gate.

The same holds for a rafting PR that names only the R-id.
Critique: a wrong result on the decided rule (user's "a": a claim with an open PR is parked). The pure case pins only the raft's side. No fixture has a raft with a PR.
Consequences: verdicts are per item while the lease is per stamp, so the two must agree. The simplest rule is that a stamp is parked when an open PR names any item holding it. That makes `parkedBy` per stamp, and `settle` reads it by stamp.
Recommendation:
- Define parked per stamp (or give every member's `match` its raft id and the raft's other members) and say so in the Design.
- Add a pure case: a member claim sharing a parked raft's stamp is `parked` from a PR that names only the R-id.
- Add a lost.spec case: a readied raft whose PR names only `R0010`, silent past STALE; `lost` lists neither the raft nor its member, and `status` tags both `[parked]`.
- Add to Rules and mutants: "a member of a parked raft is parked" (mutant: per-item match).

### F5 [high] The takeover does not re-check, at publish, the stamp it judged lost: two agents that both read `lost` both take the claim
Where: Design, Takeover ("Only an explicit lost verdict allows it (`status.canTakeOver`): it draws a stamp …"); Order ("lost work is picked first"); lost.spec:191-202.
Evidence: `setStatus` decides inside `publish.commit`'s callback from the origin text it reads there (main.luau:1410-1530: `canMove`/`canClaim` on `cur`). The verdict needs `ls-remote` and `gh`, so an implementation will compute it before publishing. Then two workers both run `./zn lost` (the lost-first rule sends every one of them to the same item):
1. A publishes stamp S1 and beats.
2. B's callback sees `preparing`, holds a "lost" verdict computed for S0, and overwrites S1 with S2.

Two live agents now hold one item with different stamps, and A's carried `status prepared` is refused only later. Nothing in the Design says the callback compares stamps, and no case or row covers it. README "Claiming across hosts" says "the push is the lock", and this path skips the lock.
Critique: zz-arch/read-own-facts-before-claiming and zz-arch/several-writers-check-the-subject: the claim must re-check its subject at the moment it writes.
Consequences: the judged stamp has to travel into the callback. A takeover that loses the race is refused with the new claim named, the same as any lost claim race.
Recommendation:
- Make `status.canTakeOver(verdict, judgedStamp, originStamp)` a pure rule (true only for `lost` with equal stamps), called inside the callback with the stamp origin holds at that moment.
- Add a pure case: equal stamps and lost is true; a changed stamp, or any other verdict, is false.
- Add an edge case: wt2's takeover publish meets a stamp changed after its verdict (for example a PATH `git` shim that, on the takeover's push, first lets `h.f.other` restamp c0010), and is refused, naming the new stamp.
- Add a Rules row (mutant: the verdict alone decides).
Lesson: zz-arch/read-own-facts-before-claiming

### F6 [medium] Claim paths and fail-safes the Design states still have no row or case (repeat of design-review-001 F6, F7, F9, F16)
Where: Design, Automatic beats ("First beats: `status <R-id> preparing`, `fold`, `recombine`, … a legacy `start`"); Takeover (`status <R-id> preparing` on a lost rafting claim, Q6); `./zn status` ("Unreadable beats: the list prints as today with `status: heartbeats unreadable` on stderr"); The dispatcher ("any other failure is written once per step"); Rules and mutants.
Evidence: no row or case covers any of these:
- the first beats of `fold`, `recombine`, `status <R-id> preparing` and `start`. The refute says their "fixtures need prepared rafts", but beat.spec already seeds a prepared raft (R0010) and a prepared issue (c0040);
- the rafting-claim takeover, whose code path differs from the issue path (members, `rememberClaim`, `canClaim(…, stored = true)`);
- the `status` list under `lsfail`: lost.spec:156-161 runs only `lost` there;
- the dispatcher's failure line.

Critique: z-design/spec-design-correspondence and z-design/results-land-on-every-path: a stated path with no case is a path an executor can skip and still pass.
Consequences: Q6 is pending. If the user vetoes it, the rafting-takeover case changes with the decision, and the Design should say so.
Recommendation:
- Add rows and cases: `status R0010 preparing` (or a `fold` into a new raft) leaves a beat of the raft's stamp; the `status` list exits 0 under `lsfail` with `status: heartbeats unreadable` on stderr; a lost rafting claim is taken over by `status <R-id> preparing`, with its members following, as Q6 recommends.
- Mark the dispatcher's failure line `reasoned` with a reason the case can't observe, or give it a case (a beat child that exits 2).
Lesson: z-design/spec-design-correspondence

### F7 [medium] Every non-READ_ONLY command now makes network calls first, and `status` makes them every time, with no time bound
Where: Design, Automatic beats ("best effort: a failure warns once"); `./zn status`, `./zn lost`; Scalability.
Evidence: an autobeat is a `fetch`, an `ls-remote`, a `git grep` and a push, run synchronously before the command (E2: `ls-remote` alone took 0.65 s). Every `status` list now runs `ls-remote`, plus `gh pr list` whenever any claim is stale. That will be common, because every prep session that ends with its PR open leaves a stale claim. Nothing bounds these calls. On a laptop with a dropped connection, or an ssh remote that hangs, `git fetch`/`ls-remote` block for the transport's own timeout, so every `./zn commit`, `spend`, `check` and `status` stalls, and "best effort" never fails because nothing returns. "Warns once" is also undefined, because the throttle is not advanced on a failure, so each command fails again.
Critique: the feature turns read-only, local commands (`status` reads `refs/remotes/origin/main` today, main.luau:1607-1618) into network commands. The tempting fix is "it's best effort", but best effort with no deadline is a hang.
Consequences: a time-out is a third "unreadable" outcome and must stay "never lost" (zz-arch rule 7). The throttle has to record a failed attempt, or each command retries.
Recommendation:
- Bound each heartbeat call (kill after a few seconds) and treat a time-out as unreadable.
- Advance the throttle on a failed attempt, so a failure warns once per interval.
- Add one case with a `git` shim that sleeps past the bound on `ls-remote`: `status` returns within the bound with the warning, and a second `./zn` command inside the interval makes no network call.

### F8 [medium] "ZN_NOW is ignored outside a spec run" switches a child out of the fence's spec mode and passes for a `lost` that fails outright
Where: acceptance/lost.spec.luau:213-216; Design, `ZN_NOW`, `ZN_BEAT_EVERY`.
Evidence:
- The case sets `PICKMAN_FENCE_SPECS = ""` for the child. `z-nile/lib/git-hooks/pre-push:20-24` refuses a network push only while that variable is non-empty; with it empty, a push to a non-local URL chains through (the reference-transaction hook keys on it too). The child is `lost`, which under the design may autobeat, and so push.
- The only assertion is `stdout == ""`. A `lost` that crashes, refuses or exits 1 passes. There is no positive control, such as the same call with the marker listing c0010.

Critique: zz-test/specs-set-host-markers-explicitly says a case may set a marker on purpose, but turning a guard marker off weakens the fence for that process. That is review item 9's concern, here small (a fixture origin, and the macOS jail still applies) but avoidable.
Consequences: the rule "honour only inside a spec run" can live in one pure function, so the edge test needs no marker change.
Recommendation:
- Put the clock rule in `heartbeat.luau` (`heartbeat.now(env, clock)` or similar) with a pure case: marker absent → the clock; marker `1` → `ZN_NOW`.
- Keep the edge case only if it asserts `r.ok`, and include the positive control: the same `lost` with the marker set lists c0010. Prefer a variable the fence does not read for the "outside" leg: pass the pure function the env table rather than clearing the real marker.
Lesson: zz-test/specs-set-host-markers-explicitly

### F9 [low] The prototype the steps say to copy is not `--!strict` and fails the type stage
Where: Implementation steps 2 ("copy `experiments/heartbeat.proto.luau`"); experiments/heartbeat.proto.luau.
Evidence: `./zn promote-check f0265` with the prototype in place: `engine/heartbeat.luau(72,38)`, `(72,45)`, `(76,14)`: `Expected this to be 'number', but got 'number?'` (the `string.find` results in `parkedBy`), and `tests/meta/architecture.spec` "every Luau file is --!strict" fails on `engine/heartbeat.luau`. The four specs themselves type-check.
Critique: z-design/prototype-engine-edits-pass-the-type-stages.
Consequences: none.
Recommendation: make the prototype `--!strict` and type-clean, re-run promote-check with it, and record it in E5.
Lesson: z-design/prototype-engine-edits-pass-the-type-stages

### F10 [low] The issue-claim `freshStamp` change has no case at its call site (repeat of design-review-001 F12)
Where: Design, Takeover ("it draws a stamp with `freshStamp("preparing")` … issue claims drew with `stamp()` before"); Rules and mutants (no row).
Evidence: `status-fresh.spec` tests the pure draw. Nothing fails if `setStatus` (main.luau:1435, `local value = stamp(to)`) keeps `stamp()`. lost.spec:197 `after ~= before` passes with `stamp()` 13,823 times in 13,824.
Critique: zz-test/kill-mutants-where-the-value-is-built.
Consequences: none.
Recommendation: add a row, plus a case where all stamps but one are taken (as round 1 suggested), or mark the row `reasoned` with the reason it can't be observed.
Lesson: zz-test/kill-mutants-where-the-value-is-built

### F11 [low] A dispatcher's `questions.md` parks only on the host that ran it; the design doesn't say so
Where: Design, Parked ("… `.cache/dispatch/<id>/questions.md` exists in the main checkout"); design-refute-001 F1 ("cross-host `questions.md` is not visible").
Evidence: the limitation appears only in the refute. README "Two ends, one stack" names workers "on the same host or another" (c0254 *captured*). Another host reads a dispatched prep waiting on the user, with no PR yet, as lost after 15 minutes and may take it over. The rule is also silent on a raft dispatch's run state (`.cache/dispatch/<R-id>/`) parking its members, which F4's per-stamp rule would settle.
Critique: z-design/accepted-risks-checked-and-decided: a limit of the user's decision (a) belongs in the Assumptions list for the user's veto.
Consequences: none until c0254.
Recommendation: add it to "Assumptions to veto" with its cost, and say that a run state under an R-id parks the raft's stamp.

### F12 [low] When the `--watch` loop's hour ends, the skills say nothing
Where: Design, The skills ("start `./zn run --time 3600 -- ./zn beat <id> --watch` in the background").
Evidence: after 3600 s the loop exits 0, and only automatic beats remain. A lead that waits on a long subagent and runs only READ_ONLY commands, or none, goes stale. The design leaves that unstated.
Critique: z-design/instructions-runnable-where-they-run: the instruction is runnable, but what follows it isn't said.
Consequences: none.
Recommendation: one sentence in the skill bullet: restart the loop when it reports its bound (Claude Code notifies on a background command's exit), or rely on the automatic beat and say which commands give it.

## Candidate lessons (for the lead)
- zz-arch: **an automatic side effect keyed to "this checkout did X once" needs an end and a subject check**, because f0265 review 002 F1 found a throttle file that made the main checkout beat every claim it ever beat, for ever, and beat a taker's new stamp. Check: what removes this entry, and does the effect re-check that its subject (the stamp, the owner) is still the one it was recorded for?
- zz-test: **a "max over all" or "count of all" assertion in a fixture that earlier cases dated in the future (ZN_NOW) proves nothing about now**, because f0265 review 002 F3's `newest` was satisfied by beats written 1,300 fake seconds ahead. Check: does every time-based assertion filter to the case's own item and to values its own run could have produced?

Verdict: changes

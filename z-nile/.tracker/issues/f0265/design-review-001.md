# Review 001: f0265 (design mode)
Inputs: prep head 7c6db879dc0e771609de0008ae0858cc1652fad8 (`tracker: prep f0265 Work heartbeat (draft for review)`), origin/main 39eea6b5; f0265.md, check.sh, acceptance/{heartbeat,beat,lost,dispatch}.spec.luau; `./zn capture f0265` (capture 5208b315, a real `tracker: new` commit, no marker); `./zn check f0265` and `./zn promote-check f0265` run in the prep worktree; z-nile/engine/{main,status,dispatcher,runner,boundcmd,wrapper}.luau, z-nile/lib/bounded.pl, z-nile/tests/lib/{fakecli,trackerfix}.luau; zz-rules, zz-arch, zz-test, z-design skills; `./zn lessons --when design --full`.

The open decisions Q1 to Q4 are fairly stated on the whole: each has a proposal, an alternative and what it costs (F13 has the framing problems). The design itself is sound in its pure core (a ref per claim stamp, judge, order, plan). The highs are in what "a claim" means on today's tracker (waiting claims and done items) and in specs that cannot pass for a correct implementation.

### F1 [high] Every claim that is waiting rather than worked turns lost 15 minutes after its last beat, and the lost-first pick sends the next agent to take over finished work
Where: f0265.md Solution ("A claim (`preparing-…` on an issue or a raft, `active-…` on a readied raft) is a lease"); Design, The edge (`--watch` "until the item's stamp on origin/main is no longer the one it started with"); The dispatcher ("while a model step runs"); Q2 (b), (c).
Evidence: a claim's stamp stays on `origin/main` long after anyone is working on it:
- a prep: the move to `prepared` "is carried by the prep PR: it only edits the local documents" (zz-rules, Sync and claim). Between opening the prep PR and its merge the issue is `preparing-…` on main, and z-design 6 says "Ask the user before merging prep they didn't request". The session that asks ends, and its `./zn run` loop ends with it.
- a rafting claim: the same, until the rafting PR merges.
- a readied raft: `ready` stamps `active-…`. It is then idle until someone runs `/z-run`, and again after `./zn done` until the human `run` gate merges the PR (`done/` lands only with the PR).
- the dispatcher stops at the `prep`, `raft` and `run` gates (exit 4) and at `questions.md` (exit 3). It beats only "while a model step runs".
Today's tracker already has this: c0118 is `preparing-raging-mellow-pink` since 1794031840, and its prep branch `prep-project-board` is in flight. Under this design it is lost 15 minutes after its session ends, `./zn lost` lists it first, the new z-design candidate rule says to take it, and `status c0118 preparing` takes it over.
Critique: the capture says "an agent *working* an item pushes a heartbeat … a stale one marks the item lost". A claim parked at a PR or a gate is not stale work, but this design cannot tell the two apart. Whether a parked claim counts as lost is a product decision, and the design makes it silently (none of Q1 to Q4 mentions it). The tempting fix is to keep the loop alive until the merge, but no session lives that long, and the dispatcher process has exited at its gate.
Consequences: any "parked" state needs a fact that says the claim is parked. It could come from an open PR on the work branch (`prep-<slug>`, `raft-<slug>`, `R…-<slug>`), which costs a `gh` call per claim in `lost` and `status` and needs a credential and network: unknown must then mean "not lost", per rule 7. Or it could be a marker that the PR-opening step writes and that merge, close or `stop` clears. That marker is a new kind of ref under the prefix, `parse` has to accept it, and something must remove it when the PR closes without merging.
Recommendation: escalate to the user as Q5, with these options:
- (a) A claim whose work PR is open (or which waits at a dispatcher gate or on `questions.md`) is *parked*: never lost, and never taken over. It is shown as `[parked]`.
- (b) Only claims with no PR count. The takeover refuses when `origin/<work branch>` exists or has an open PR.
- (c) Accept that parked claims read as lost, and drop "take lost work first" from the skills.

Whichever the user picks needs these spec cases: a claim with an open PR on its prep branch, silent past STALE, is not listed by `lost`, and `status <id> preparing` refuses it, naming the PR; and a readied raft with no beat for STALE seconds is handled the way the decision says.

### F2 [high] lost.spec cannot pass for a correct implementation: the seeded never-beaten claim c0050 is the most silent claim, so it sorts first and is lost when the spec expects nothing to be
Where: acceptance/lost.spec.luau:74 (c0050 seeded `preparing-lucky-violet-heron`), :96, :104, :105.
Evidence: `T0 = os.time()` is read when the spec loads, so c0050's claim commit (the fixture seed) lands at about T0. At `late = T0 + 600 + STALE + 1`:
- c0050's silence is about `STALE + 600` (`since` is its landing, and it has no beat).
- c0010's silence is `STALE + 1` (its last beat was at T0+600).

Design, Order: "lost before live, longest silent first". So the first line of `status` is c0050's, and line 96 (`string.sub(first,1,5) == "c0010"`) fails. In the next case, `lost` at `late` and at `late + STALE` must print `""` (lines 104 and 105), but c0050 is lost at both moments, so stdout is `c0050 preparing …`. Case 5 (lines 110 to 113) then requires c0050 to *be* lost, which rules out the only shapes that would pass 96 and 104 (grandfathering, no ordering). No implementation passes all of AC3.
Critique: the Rules table marks every lost.spec row `reasoned`, because the edge was "not prototyped". Its stated check was that the specs "fail on assertions (unknown command `beat`, no ref on origin)", and that cannot catch cases that are wrong in themselves. The tempting fix is to delete c0050 from this fixture, but that loses the never-beaten case where it matters, in the same listing as a beaten claim.
Consequences: assertions must not depend on how claims the case does not own are ordered or listed.
Recommendation: keep c0050 and make the assertions say what the rule says:
- At `late`, c0010's line carries `[lost ` and comes before every line without `[lost `; c0050 comes before c0010 (longest silent first), which pins the order rule end to end.
- In the revive case, assert on c0010's line alone (`has(lost, "c0010")` false at `late` and at `late+STALE`, true at `late+STALE+1`).

Then run lost.spec against a prototype of the `lost` and `status` edge (two commands over `heartbeat.judge`, much less than the full 480 lines), and record that the cases pass and that the listed mutants fail.
Lesson: z-design/prove-specs-pass-on-a-prototype

### F3 [high] beat.spec's `ready` case fails on its fixture, not on the missing feature: c0040 is not a member of R0010
Where: acceptance/beat.spec.luau:66-68, 110-111.
Evidence: `./zn check f0265` prints `beat.spec:111: ready R0010 failed (1): R0010 has no member issues`. `store.members` (store.luau:215) lists the issues whose own `raft:` line names the raft, and `trackerfix.stub` writes `raft: ` empty for c0040. The raft's `issues: [c0040]` alone makes no member, so `ready` refuses whatever f0265 builds.
Critique: this is a "fails for the right reasons" miss (z-design 4, Verify the wiring). The Unknowns section says every edge spec fails on assertions, which this case doesn't. The same fixture is copied into lost.spec (:70-73) and is unused there, so it has no effect there.
Consequences: once c0040 has `raft: R0010`, `ready` runs its full checks (a check in `check.sh`, every member `design: ready`, and prepared on origin), and the case then has to pass all of them.
Recommendation: seed c0040 with `raft: R0010` (a `string.gsub` on the stub, as `issue()` already does for `design:`), run the case with the beat call stubbed out to confirm that `ready` itself succeeds in the fixture, and record it.
Lesson: z-design/prove-specs-pass-on-a-prototype

### F4 [high] Done items keep `status: active-…`, and the design keys a claim on the stored stamp: a naive `lost` lists every finished raft, `beat` beats done items, and no fixture seeds a done item
Where: Design, The edge (`beat` "refuses … an item … whose stored `status:` is not `preparing-…`/`active-…`"; "the claimed stamps of all items (one `git grep`)"); Claim type; beat.spec and lost.spec fixtures.
Evidence: `git grep -nE "^status: (preparing|active)-" origin/main -- '*/.tracker/*'` returns about 30 hits under `done/`, for example `pickman/.tracker/issues/done/c0051/c0051.md:11:status: active-quiet-indigo-lucky` and four done issues that share `active-indigo-walrus-quiet` (c0155, c0159, c0164, c0170). `status.effective` makes them `done` only through the folder. Under the rule as written:
- `beat c0051` is accepted, because its stored status starts `active-`.
- A claim list built from the grep, or from the stored prefix, makes every done item a lost claim (silent since its `ready` commit).
- `plan`'s "claimed" set keeps every finished raft's last beat on origin for ever.

The refusal cases seed only new (c0020), prepared (c0040) and missing (c9999) items, and lost.spec seeds no done item, so all of these mutants pass every spec.
Critique: this is an acceptance criterion that a wrong implementation passes, and "who holds a claim" is the core definition this feature rests on. The tempting fix, "exclude `done/` paths from the grep", fixes the reader but not the definition.
Consequences: one definition of a claim (state `preparing` or `active` by `statusLib.effective` with the item's folder), used by `beat`'s refusal, by `judge`'s claim list and by `plan`'s claimed set. The retired-raft folder (`rafts/retired/`) needs the same rule.
Recommendation: state that definition in the Design. Then add:
- to beat.spec and lost.spec, a done item (in `issues/done/`) whose stored status is `active-<words>`: `beat` refuses it ("done"), and `lost` and `status` never list it;
- to heartbeat.spec, a pure `plan` case where a beat of a stamp that only a done item carries is deleted (the edge passes `claimed` without done stamps; pin that at the edge with the beat.spec case above).

Lesson: zz-test/seed-every-enumerated-case

### F5 [high] The loop the skills prescribe can't start, and at the longest allowed bound it still lets a live prep go lost after about an hour
Where: Design, The skills (z-design step 1: `./zn run --time 14400 -- ./zn beat <id> --watch`); The edge ("the loop is always started as `./zn run --time <s> -- …`").
Evidence:
- `z-nile/lib/bounded.pl:20` has `( $DEFAULT_TIME, $MAX_TIME, $GRACE ) = ( 60, 3600, 2 )`, and line 26 reads `usage("--time must be 1..$MAX_TIME seconds (got $v)")`. zz-test says `--time` is "at most 3600". The prescribed command exits with a usage error.
- With `--time 3600`, the loop ends after an hour. A prep has no other beat source, because prep commits use plain `git commit`, not `./zn commit` (zz-rules, Landing a change 1), and a design with up to five review rounds runs for hours. The claim is lost about 75 minutes in while the agent is still working, and the lost-first rule then hands it to someone else.
- AC5 greps only for `./zn beat` in the skill, so it passes with the broken line.

Critique: an instruction that can't run where it runs. The tempting fix, "use 3600", hides the hour limit.
Consequences: an interactive session needs either a beat source that lives as long as the session, or an instruction that renews the loop.
Recommendation: pick one and specify it, with spec cases:
- (a) Every `./zn` command run in a worktree that remembers a claim (`.cache/tracker-claim-<id>`, which `status <id> preparing` already writes) beats that claim when its last beat is older than INTERVAL. It costs one `ls-remote` at most every INTERVAL. Case: a `./zn list` run in `wt` at ZN_NOW = last + INTERVAL + 1 writes a beat.
- (b) The skills restart `./zn run --time 3600 -- ./zn beat <id> --watch` every hour and say so, and AC5 greps for `--time 3600`.
- (c) Raise bounded.pl's cap for this one command. That widens a guard, so it goes to the user.

Lesson: z-design/instructions-runnable-where-they-run

### F6 [medium] `--watch`, `commit`'s beat and four of the six claim paths have no Rules and mutants row and no case; the hook lets an unwrapped `./zn beat --watch` run for ever
Where: Rules and mutants table; Design, The edge (`--watch`, "First beat on every claim path", "`./zn commit` in a raft's worktree beats the raft too"); `z-nile/engine/boundcmd.luau:457`.
Evidence:
- No row or case covers these rules: `--watch` repeats every `ZN_BEAT_EVERY`, exits 0 and says so once the stamp changes, and a failed beat is said on stderr and retried.
- `./zn commit` beats the raft.
- `new raft`, `fold`, `recombine`, `status <R-id> preparing` and legacy `start` each write a first beat.

beat.spec covers only `status <id> preparing` and `ready`. `boundedish` returns true for any program named `zn`, so the hook passes `./zn beat c0010 --watch` in a background call with no `./zn run`. `boundcmd.luau` is not a Touched module.
Critique: behaviours in the Design with no case that fails without them (z-design/spec-design-correspondence; z-design/results-land-on-every-path names these same paths). A `./zn` command that never ends breaks the hook's premise that every `./zn` command bounds itself (zz-arch/children-need-a-lifeline).
Consequences: if `--watch` refuses to run without a bound (for example when `ZN_BOUNDED_DEADLINE` is unset), the dispatcher and the specs must set it.
Recommendation:
- Add rows and cases: `--watch` with `ZN_BEAT_EVERY=1` writes two beats and exits 0 with a message once another clone restamps the item; `./zn commit` in a raft worktree leaves a beat; `fold` and `new raft` over prepared issues leave a beat of the raft's stamp.
- Either make `--watch` refuse unless it runs under `./zn run` (it can read `ZN_BOUNDED_DEADLINE`), or add `zn beat … --watch` to boundcmd's refused forms, with a case in the hook's spec. Add `z-nile/engine/boundcmd.luau` to Touched modules.

### F7 [high] "Unknown is never lost" is pinned only on `lost`, not on the takeover it exists to guard; an unparsable ref under the prefix has no defined outcome
Where: Design, The edge (`lost`, `status` list, takeover); lost.spec:132-139; Q3; E2.
Evidence:
- The only unreadable case points `origin` at a missing repository. The takeover can't be tried there, because its publish fails too.
- A takeover that treats an `ls-remote` failure as "no beats" reads the claim as silent since it landed, so lost, and takes over a live claim. It passes every spec.
- The `status` list's "prints as today, with `status: heartbeats unreadable` on stderr" has no case either.
- `parse` returns problems for malformed refs under the prefix, but nothing says what `lost`, `status`, the takeover or `plan` do with them. `plan` never deletes them, so one stray ref stays for ever. E2's probe was itself named `refs/zn/hb/probe-f0265/1`, a malformed ref under the prefix; it is gone now (`git ls-remote origin 'refs/zn/*'` prints nothing), but U1's probe uses the same pattern.

Critique: this is zz-test/pin-fail-safes-where-they-act: the fail-safe has to be pinned where the decision is taken. A wrong takeover passes AC3.
Consequences: if a parse problem makes every reader refuse, one stray ref blocks `status` for everyone. If it is ignored everywhere, a takeover proceeds on input it could not read.
Recommendation:
- Fail closed only at the takeover: a parse problem or an unreadable `ls-remote` refuses `status <id> preparing` on a preparing claim, naming the ref or git's message. `lost` and `status` print, with the problems on stderr.
- Probes use a name outside the prefix (`refs/zn/probe/…`).
- Add cases with a PATH `git` shim that fails only `ls-remote`, as fakecli's `bin/git` does for fetch: the takeover of a long-silent claim is refused and mentions heartbeats; the `status` list exits 0 with the warning; and, with a malformed ref pushed to the fixture origin, the takeover is refused while `lost` still lists the lost claim and names the ref on stderr.

Lesson: zz-test/pin-fail-safes-where-they-act

### F8 [medium] `beat` reads claimed stamps from the local `origin/main` with no fetch, so a checkout that hasn't fetched since another host claimed deletes that claim's beats on every tick
Where: Design, The edge (`beat`: "reads the claim stamp from `origin/main`, the claimed stamps of all items (one `git grep`), the existing beats (one `ls-remote`)"); Scalability (no fetch listed); Plan ("every beat of a stamp no claim holds").
Evidence: worktrees share `refs/remotes/origin/main`, and it moves only when something fetches. Host A's `--watch` loop runs for 40 minutes while A runs no `./zn` command that fetches. Meanwhile host B claims c0300 and beats. Each of A's beats sees `refs/zn/hb/<c0300's stamp>/…` with a stamp absent from A's grep, and deletes it. c0300 then has no beat for most of each 5-minute window and reads as silent since its landing, so it is lost after 15 minutes while B is alive, and a third agent takes it over. The `--watch` exit test ("the stamp on origin/main is no longer the one it started with") is equally blind without a fetch.
Critique: the prune is a delete of another agent's state, decided from a stale read. The tempting fix, "fetch first", leaves a window between the fetch and the push.
Consequences: with a fetch and a grace period, a given-back claim's beats stay up to STALE longer, which is harmless (no claim holds them).
Recommendation:
- `beat` fetches `origin main` before it reads (a fetch is allowed in the main checkout), and `--watch` fetches on every tick.
- `plan` deletes an unclaimed stamp's beat only when it is older than `STALE` (pure case: an unclaimed beat at `now - 60` is kept, one at `now - STALE - 1` is deleted).
- Edge case: a claim made in `h.f.other` after main's last fetch keeps its beat after `beat c0010` runs in `h.f.main`.

### F9 [medium] A takeover leaves the old claimant's branch, PR and give-back unaddressed, and a raft's rafting claim has no takeover rule
Where: Design, The edge (takeover); Q2 (b); Non-goals ("Ending, giving back … a lost claim by itself").
Evidence: Q1 accepts that a laptop asleep for over 15 minutes is marked lost.
- When the old agent wakes, its `--watch` exits ("taken over"). But setStatus lets its carried `status <id> prepared` through: for an issue it checks only that the origin state is `preparing` (main.luau:1505-1530), so it opens a second prep PR, which conflicts on `status:`.
- It may also run `status <id> new`, which is "open to anyone", and end the taker's claim.
- The taker's `./zn worktree prep-<slug>` on another host cuts a new `prep-<slug>` from origin/main while `origin/prep-<slug>` holds the old agent's pushed work, so the taker's push is non-fast-forward.
- For a lost rafting claim (`preparing-…` on a raft), `fold` refuses a raft "being prepared", `status <R-id> preparing` hits `canMove(preparing, preparing) = false` and `canClaim(... stored = true) = false`, and `release` needs the remembered claim or `--force`. The design says "a lost preparing claim can be taken over" without saying which of these paths changes.

Critique: this is zz-arch/claims-name-who-else-can-claim. A takeover is a new way in, and every way out and every collision has to be named. Whether the taker adopts or discards the old branch is a product decision.
Consequences: refusing the old agent's carried move when the stamp changed is a new refusal on an existing path (z-design/new-refusals-reach-every-caller).
Recommendation:
- Escalate to the user: should a taker of a lost claim continue from `origin/prep-<slug>` (or the raft branch), or start fresh and leave the old branch alone?
- Design: the carried `status <id> prepared` refuses when the stamp on origin differs from the one this checkout remembers, naming the takeover. Say whether `status <R-id> preparing` can take over a lost rafting claim, and how members and the remembered claim files follow.
- Cases: the old worktree's `status c0010 prepared` after the takeover is refused and names it; a raft's lost rafting claim is taken over (or refused, as decided).

### F10 [medium] AC4 passes with one beat when the step starts, and its proof waits on a fixed sleep
Where: acceptance/dispatch.spec.luau:41, 45-53.
Evidence: the fake step is `sleep 4`. The spec asserts exactly one ref with `started <= epoch <= now`. A dispatcher that beats once before it starts the CLI, or once after the CLI ends, leaves one such ref and passes, so "while the step works" is not checked. zz-test (Writing specs for speed) says "no fixed sleeps to let something finish".
Critique: AC4 can be passed by a wrong implementation.
Consequences: a rendezvous needs the fake step to read origin's refs.
Recommendation: make `script.sh` a bounded poll. Inside the step, it waits up to 10 s, printing, until `git ls-remote origin "refs/zn/hb/$STAMP/*"` shows a beat dated at least 2 s after the step's own start, writes `$FAKE_DIR/beat-seen`, and exits. The spec asserts that the marker exists and that one ref is left. The beat-at-start mutant leaves no such beat, and the beat-at-end mutant times out.

### F11 [medium] AC5's README half passes on today's README, and the z-raft and z-ready bullets are not checked
Where: check.sh AC5 (`g "lost" README`, `g "f0265" README`).
Evidence: `grep -n lost z-nile/README.md` already matches line 59 ("a lost race means taking the next item"), so the "lost-first pick" part of the label passes before any change. The Design adds bullets to z-raft and z-ready that AC5 never reads.
Critique: zz-test/criterion-fails-on-todays-file.
Consequences: none.
Recommendation: grep for the sentence the change adds in the README's `### Order` section (for example ``./zn lost``), match within that section as c0259's spec does, and grep z-raft and z-ready for ``./zn lost`` (or ``./zn beat`` for z-raft).
Lesson: zz-test/criterion-fails-on-todays-file

### F12 [medium] The design assumes that claim stamps are unique on origin/main; issue claims are not drawn that way, and two live claims that share a stamp keep each other alive
Where: Design, The beat, Name ("already unique on `origin/main` (claims.taken, `status.fresh`)").
Evidence: `setStatus` draws `local value = stamp(to)` (main.luau:1435). Only `freshStamp` (main.luau:584, used for `new raft`, `fold`, `recombine` and `ready`) checks `claims.taken`. `status.luau` has 24 words, so 13,824 stamps. Origin/main holds about 20 live `preparing-…` claims today, which gives roughly a 1.4% chance that two of them share a stamp. When they do, one live agent's beats keep the other's dead claim alive, and `plan` treats both as one lease. The takeover's "fresh stamp" has the same gap: it can redraw the old one.
Critique: a premise of the lease id that is false for the most common claim path.
Consequences: drawing issue claims with `freshStamp("preparing")` costs one `git grep` per claim, which `freshStamp` already does for rafts.
Recommendation: the Design says `status <id> preparing` and the takeover draw with `freshStamp("preparing")`, and adds a pure or edge case: with every stamp but one taken (stubbing `stamp` or `taken`), the claim takes the free one.

### F13 [low] Open decisions: Q3 calls the author's constraints "captured" and leaves out one option; Q2's "(a) alone" would need a Scope decision; z-ready has no lost claim it can act on
Where: Design, Open decisions Q2, Q3; The skills (z-ready "candidates: lost first").
Evidence: the capture is the one Problem line. Its Non-goals and Solution are empty, so the constraints Q3 says a file or a branch would break are the zz-rules direct-push exception and the author's own judgment, not the capture's. Q3 also leaves out the work branch itself (each `./zn commit` pushes the raft branch, and the prep branch is pushed too) as a sign of life. Q2's "(a) alone" makes lost work visible but does not pick it first, which shrinks a captured outcome and would need a `Scope decision` line. A lost claim is `preparing` or `active`, and z-ready only readies `prepared` rafts, so "lost first" there names nothing it can act on.
Critique: the user should choose from options that are framed accurately.
Consequences: none.
Recommendation: reword Q3 ("rejected for the direct-push exception and the main checkout's churn") and add the work-branch option with its cost (no ref for a claim with no branch yet; commit times are the author's clock). Note under Q2 (a) that it needs the user's Scope decision. Drop the z-ready bullet, or say which lost state it acts on.

### F14 [low] The clock risk is accepted by the author on a premise SETUP.md doesn't state, and `ZN_NOW` in the environment makes every claim takeover-able
Where: Design, Lost ("ntp-grade clocks are assumed (accepted risk: checked against SETUP.md's hosts …)"); `ZN_NOW`.
Evidence: SETUP.md lists macOS, Linux and GitHub runners and says nothing about time sync. c0254 (workers on several hosts) is captured. A skew over 600 s lets a live claim be taken over, which weakens the new guard. A stray `ZN_NOW` (from a spec shell, an exported variable) reads every claim as lost, and zz-arch rule 7 says configuration that widens a guard is not taken from what a branch or an agent can set.
Critique: z-design/accepted-risks-checked-and-decided: a risk that weakens a guard carries a `Decided with the user` line.
Consequences: honoring `ZN_NOW` only inside a check (the runner's marker) keeps it out of real use.
Recommendation: add the skew risk to the open decisions for the user. Honor `ZN_NOW` and `ZN_BEAT_EVERY` only when the spec runner's marker is set (as the dispatcher limits fakes to `.cache` CLIs inside a check), with a case where `ZN_NOW` set outside a check is ignored.

### F15 [low] The README roadmap row will say `designed` for a feature its own PR builds
Where: Design, The skills ("its Roadmap gets the row `work heartbeat | f0265 | designed`").
Evidence: README, How it should work: "**exists** (built and on `main`) … A feature's PR changes its own roadmap row and every label that names it." f0265's PR lands the code, so the row should say `exists`. AC5 and c0259's spec accept either word.
Critique: z-design/status-labels-need-a-tracker-fact.
Consequences: none.
Recommendation: the row says `exists`, and the Order sentence is labelled *exists* (f0265).

### F16 [low] Shared stamps, minute rounding and the dispatcher's failed beats are left to the executor
Where: Design, The edge (`lost`: "one line per lost claim, `<id> <state> <minutes>m`"); The dispatcher ("its refusal ignored").
Evidence: a raft and its members share one stamp (R0061, c0134, c0135 and c0137 all carry `active-pink-indigo-copper` on origin/main). The design doesn't say whether `lost` prints one line per stamp or per item, or how minutes round. "Refusal ignored" doesn't separate a refusal (no claim yet) from a push failure (U1, network), so a dispatcher whose beats always fail says nothing.
Critique: executability: two executors would build different outputs, and `./zn work` (c0253) is said to consume them.
Consequences: none.
Recommendation: one line per item, with members after their raft and the stamp's verdict shared (or per stamp, naming the raft), minutes floored. The dispatcher logs a non-refusal failure once per step in the step's log or state. Pin the line form with one `lost` case on a readied raft.

### F17 [low] The experiment record doesn't show bounded runs, and the E5 prototype that the `run` rows cite was not kept
Where: Unknowns & experiments, E1 to E5; Rules and mutants (`run` rows).
Evidence: E1 to E4 give results but not the commands, and don't say they ran through `./zn run --time` (review item 12). E5 says "The prototype is not committed", so no reviewer can check the eight `run` rows (zz-review/claims-cite-a-prototype-holding-the-files).
Critique: the record can't be audited.
Consequences: none.
Recommendation: record each experiment's command as run (`./zn run --time 30 -- …`), and keep the E5 prototype as `experiments/heartbeat.luau` (prep's file, not counted in `size:`), so the `run` rows can be replayed.

## Candidate lessons (for the lead)
- z-design: **a lease or liveness rule names every state in which a claim is held but not worked** (a PR waiting for merge, a gate, a readied raft not started, a question to the user), because f0265 review 001 F1 found that each of them read as dead. Check: for each state in which the claim's stamp stays on origin/main, who beats it, and if no one does, is it meant to read as lost?
- zz-test: **a fixture that seeds a claim in the background must be checked against every listing assertion of the later cases** (here, a never-beaten claim outranked the case's own), because of lost.spec F2. Check: does any seeded item change what an "empty" or "first line" assertion sees later in the spec?

Verdict: changes

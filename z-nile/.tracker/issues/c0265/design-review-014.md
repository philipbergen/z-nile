# Review 014: c0265 (design mode)
Inputs: prep head fdd5a19e (`tracker: prep c0265 answer redesign review round 2 (heartbeat branch)`). This is round 3, the final round of the restarted count. I read c0265.md, check.sh, acceptance/{heartbeat,beat,lost,edge}.spec.luau, proofs/{dispatch,race}.spec.luau, experiments/heartbeat.proto.luau, design-review-012/013 and design-refute-012/013, and `git diff a79f8eb8..HEAD`. In the engine I read `cmd.worktree` (main.luau 3692-3755), `setStatus`'s memory (1560-1592), `READ_ONLY` (5989) and `stop`'s subjects (4785, 4853). In the skills I read z-design step 1 and z-run step 3, and zz-rules' Run state (line 178). I ran `./zn lessons --when design` and `--skill zz-review`.
Dropped from review-013: F6 (now Reading (2) under Assumptions to veto: the user's call), F8 (E8 names 53 spec files, and the directories it lists hold exactly 53; the unhooked paths are stated honestly and left to Phase 1), F9 (the shim arm now matches only `:refs/heads/hb/$FAKE_OLDSTAMP`) and F11 (now Reading (1)).
Capture: `./zn capture c0265` prints `(no capture commit: first add)`. That is the user's #258 rewrite, so it is not a confirmed capture, and I judged it from that commit. The title, Problem and Solution are unchanged except for added `Decided with the user` lines and one Solution bullet of design detail. Every captured outcome has a Design and a criterion. Finding F1 is about how far the design meets the 2026-11-08 decision.

Replays (from z-nile, with the prototype copied to `engine/heartbeat.luau` and deleted after; `git status --short` is empty):
- `../zn run --time 900 -- lune run tests/run -- <spec>`: heartbeat 20/20.
- Against the unchanged engine, beat (1/11), lost, edge (1/5), dispatch (1/2) and race (1/5) each pass their setup case. Every other case fails on the missing `beat`/`lost` (usage text).
- `./zn promote-check c0265`: OK.
- `git hash-object` of the proofs: `6fd10bdf…` and `5ae72235…`, which match AC4 and AC5. `bash -n check.sh` is clean.

Round 2 (review 013) as answered in the documents:
- F2: fixed. `prs.json` is reset to `[]` before the stop-then-ready case. With it R0010 is lost at LATE + 14·STALE, since its only beat is ready's at T0 and the main checkout never autobeats.
- F3: fixed. With "any failed write is said", the race proof's single `pushfail` shows on stderr, and the retry lands. Its consequence is F5.
- F9: fixed.
- F1: the answer chose "the main checkout writes the memory". beat.spec's last case now passes because c0095 is claimed in wt and main never adopted it. The consequence of the choice is F4.
- F4: fixed for an old owner in a different checkout. The adopt form is pinned in lost.spec. It is open for the same checkout (F1), and the AC6 half was not done (F2).
- F5: not fixed, and the answer contradicts the Design (F3).
- F7: `ready`'s drop was replaced by the pruner, and `done` drops the entry. There is still no case (F6).
- F10 (a) and (b): still open (F7).

Walk (a correct implementation of the design as stated), step by step:
- beat.spec passes:
  - at T0+1000 the worktree's lease is its remembered T0 sha, while the branch holds main's T0+600 commit, so the push is rejected, the rejection is said, `rejected` retries on the sha there, and the push lands;
  - the c0095 case refuses a bare beat (no memory in main), refuses `--stamp <wrong>` with the taken-over text, and beats with the right stamp.
- lost.spec passes. Checked along the way:
  - the parking by questions.md and by the PR naming only R0010;
  - `active-brisk-amber-otter` is pruned by wt2's c0070 claim;
  - at at+2·STALE the `#beatRefs()` count is unchanged, since every remaining branch is claimed;
  - the give-back keeps the entry, so the next command says "claim ended";
  - the stop subject is new text that no promoted spec pins (grep of `tracker: stop` in z-nile/tests: only c0115/freeze's own commit).
- edge.spec passes:
  - the restamp fires on `{sha}:refs/heads/main` (publish.luau:602);
  - the beat race fires only on c0071's push, and a no-lease force push would recreate `hb/<old>` and fail;
  - the create-only race fails without the re-read.
- proofs/dispatch and proofs/race pass.

### F1 [high] On one host the taker works in the old worker's worktree. Its first command there revives the lost claim, and where a takeover does go through (`--adopt --replace`), the old process in that worktree is never told. This contradicts the 2026-11-08 decision.
Where:
- The lease and ownership: "So an old owner that comes back in the checkout that owned the claim is told, whichever form it uses", and "`--adopt --replace` … z-run uses it in a worktree that held the raft before a `stop` and `ready`".
- Automatic beats: "Every `./zn` command … first reads the worktree's entries … it beats that item".
- Assumptions, Takeover: "`./zn worktree prep-<slug> --from origin/prep-<slug>`".
- z-design step 1: `cd "$(./zn worktree prep-<slug>)"`, then `./zn sync` first.
- z-run step 3: `cd "$(./zn worktree <R>)"`.
- `cmd.worktree` (main.luau 3725-3729): when the worktree exists, it prints its path and returns, and `--from` is ignored.
- Problem: Decided with the user (2026-11-08), "this would tell the process that it lost the ownership if it comes back around".

Evidence:
- **Prep, the common case** (one host is the whole scope today: several hosts is c0254). An agent claims c0010 in `.worktree/prep-x` (entry `S1 E sha`) and dies. Sixteen minutes later `./zn lost` lists c0010, and the next worker follows z-design: `cd "$(./zn worktree prep-x)"` returns the dead agent's checkout, then `./zn sync`. Its autobeat reads the entry: origin still shows S1, and the epoch is more than 300 s old, so it **beats S1**. The following `./zn status c0010 preparing` is refused: "claim alive: last heartbeat 0m ago". Every worker that enters that worktree revives the claim again, so a lost prep on its own host can never be taken over by the prescribed path.
- **Active raft.** After `stop` then `ready` (S2), the new z-run enters the same fixed `.worktree/R0010`. Its first command prints "R0010's claim was taken over (now S2): stop working it" to the *taker*. `--adopt --replace` then rewrites the memory and the entry to S2. When the old session wakes in that worktree (a suspended laptop, a session waiting 20 minutes on a permission prompt), its bare `beat`, its `--watch`, its autobeat and its `done` all find memory S2 equal to origin's S2. Nothing tells it, and two sessions work one branch.
- The old z-run session that re-invokes `/z-run` runs the same `--adopt --replace` the skill gives the taker, and adopts the taker's claim.
- lost.spec takes every claim over from a second worktree, `wt2`, so no case reaches this path.

Critique: ownership is per checkout, and on one host the taker and the old owner share the checkout. The Design's sentence quoted above is false on its own prescribed path. The fix the author will be tempted to make is "the taker uses another worktree". For a prep that means a new branch name (the PR branch is `prep-<slug>`). For a raft it is impossible, because `raftBranch` is fixed and git refuses to check one branch out twice.

Consequences:
- Part (a) (the revive) has a local fix: the autobeat never beats a claim that is already stale.
- That changes edge.spec's beat-race case, whose `due = now + 1000` is past STALE. It would need `now + 600`.
- A returning owner that was silent for more than 15 minutes must then beat explicitly, after being told. That is the user's intent.
- Part (b) has no fix that keeps per-checkout memory: something must tell two processes in one directory apart.

Recommendation:
- (a) State it: the autobeat, and only the autobeat, does not beat a claim whose newest beat (else its landing time) is past STALE. It says once `<id>'s claim is lost (silent <n>m): ./zn beat <id> revives it` and keeps the entry. The explicit `beat` still revives (lost.spec "a beat revives" uses it).
- (a) Add a lost.spec case: a stale claim's own worktree runs `sync`, the branch's tip is unchanged, and a takeover from that worktree then passes. Move edge.spec's due to `+600`, and add a row: "the autobeat revives a lost claim".
- (b) escalate to the user. The options:
  1. a takeover refuses in a checkout that remembers the stamp it takes over, and `stop` of a lost raft moves the old worktree aside (`git worktree move .worktree/R0010 .worktree/R0010.lost-<stamp>`; the old process's cwd follows the move, keeps memory S1 and is told). Cost: a worktree move in `stop`, a prep taker on a new branch `prep-<slug>-<n>` from `origin/prep-<slug>`, and the PR's branch changes;
  2. bind the memory to a session id that every session and the dispatcher export, instead of the checkout. Cost: hooks, the dispatcher and the runner, and a plain terminal has no id;
  3. accept that a same-worktree return on one host is not detected, recorded as a `Decided with the user` line, with the Design's "whichever form it uses" sentence narrowed to match.
Lesson: zz-arch/automatic-effects-have-an-end-and-a-subject-check

### F2 [high] AC6 can be passed by z-run skill text that never beats: the raft worktree has no memory, and "the same loop for the raft" refuses there
Where: The Skills ("z-run … the same loop for the raft"); The lease and ownership ("A checkout with no memory (… a raft worktree made after `ready`) refuses a bare `beat <id>`"); check.sh AC6, which greps z-run only for `./zn beat`, `--time 3600`, `./zn lost` and `re-adopt`; review 013 F4 ("AC6 should grep `--adopt …` in z-run"), not answered.
Evidence:
- After `ready` (main checkout) the raft worktree has neither `.cache/tracker-stamp-<R>` nor an entry. `ready` is not a claim publish into it.
- A z-run skill line `./zn run --time 3600 -- ./zn beat R0010 --watch`, run in the background, re-adopts the raft if `./zn lost` lists it. That line passes AC6.
- At run time the loop exits 1 with "not held by this checkout", and the autobeat has nothing to beat. An interactive raft execution then reads lost 15 minutes after `ready`, and the skills send the next lost-first worker to `stop` and `ready` a live raft.
Critique: the whole liveness of interactive raft execution rests on one word in a skill that no criterion checks.
Consequences: z-run must say which form it uses and when: a plain `--adopt` in a fresh worktree, and `--replace` only under F1's outcome. Saying `--replace` unconditionally reopens F1(b).
Recommendation: in The skills, make z-run's step 3 run `./zn beat <R> --adopt` before the loop, and state the `--replace` condition F1 settles. In AC6, add `g "--adopt" "$R/skills/z-run/SKILL.md"`, and do the same for zz-execute if its loop line runs in the raft worktree. Add a row: "z-run's loop in a raft worktree without adoption refuses".

### F3 [medium] (repeat of review-013 F5) A dispatched step that makes its own claim is beaten by nothing between its own commands, and the Design's answer contradicts itself
Where: Assumptions, Readings (3) ("kept alive by that agent's own `./zn` commands **and its loop**"); The dispatcher ("Under `ZN_DISPATCH=1` the step starts no loop"); The skills (z-design: "start … `--watch` … unless `ZN_DISPATCH=1`").
Evidence:
- A headless `./zn dispatch c0300` z-design step claims `new` c0300 inside the step. The dispatcher's `--stamp <S>` has no S, and the agent is told not to loop. Its only beats are its own `./zn` commands.
- A 15-minute stretch of reading and writing without one reads lost. A lost-first worker takes it over, and the result is two preps of one issue.
- "its loop" does not exist under the dispatcher.
Critique: this is the most common dispatched path, and the liveness lesson's question ("who proves it alive?") has no answer for it.
Consequences: the dispatcher knows the step's worktree (`st.worktree`). Reading S from that worktree's `.cache/tracker-stamp-<id>` on each tick fixes it: absent means not claimed yet (skip quietly), present means fixed from then on. "S is the first stamp seen on main" would adopt a foreign claim.
Recommendation: state that rule, or allow the loop under `ZN_DISPATCH=1`. Add a dispatch.spec arm in which the fake step claims mid-step and a beat of its stamp arrives after the claim, then re-pin AC4. Fix Readings (3).
Lesson: z-design/liveness-names-held-not-worked-states

### F4 [medium] The main checkout's claim memory has no end, and it blocks the dispatcher's later adoptions of the same item
Where: The lease and ownership ("`--adopt` … writes the memory in the adopting checkout, the main checkout included"; "Adoption never overrides a remembered different stamp"; "`--adopt --stamp <S>` … refuses when `main` no longer shows `<S>`"); When the branch is deleted (`done` drops "the memory of the worktree"); Automatic beats ("the dispatcher's and `ready`'s beats there are ref pushes only"); AGENTS.md's list of files `./zn` writes in the main checkout (not a Touched path).
Evidence:
1. The dispatcher in the main checkout beats R0010's z-run with `beat R0010 --adopt --stamp S1`, and main now remembers S1.
2. The raft goes lost and is stopped and readied (S2). `./zn dispatch R0010` runs the taker's z-run, whose ticks are `--adopt --stamp S2`.
3. Main's memory S1 differs from origin's S2, so by "adoption never overrides a remembered different stamp" the adoption is refused with "taken over (now S2)".
4. The dispatcher then stops beating and says the claim was taken over, which is false. The new claim reads lost 15 minutes later, and the stop-then-ready loop repeats.
5. The same happens after any give-back and re-claim of an item the dispatcher once beat. Nothing ever removes main's memory files.

Critique: the lesson's own question, "can the main checkout ever hold one?", is now answered yes, with no end. The answer to review 013 F1 also contradicts the Design's "ref pushes only" line.
Consequences: an explicit `--stamp` is the holder's record. It does not need the memory, and making it per call removes the poisoning. A human's plain `--adopt` in main then needs either the same per-call rule (review 013 F1's recommendation, which beat.spec's c0095 case passes as well) or a stated end (`stop`, give-back, `done` and the takeover remove main's memory too).
Recommendation: `--adopt --stamp` never reads or writes the memory, and neither does `--adopt` in the main checkout. Add a beat.spec case: main runs `--adopt --stamp S1`, the item is re-claimed (S2), and `--adopt --stamp S2` beats. If the memory stays in main, state what removes it, and add AGENTS.md to Touched.
Lesson: zz-arch/automatic-effects-have-an-end-and-a-subject-check

### F5 [medium] With "any failed write is said", the remembered-sha lease prints a rejection on most worktree beats of a dispatched step
Where: The lease and ownership (the one lease rule, remembered sha first; "any failed write is **said** … even when the retry then succeeds"); heartbeat.spec "the lease is the sha this checkout last wrote…" (it expects lease `mine` while the branch holds another sha).
Evidence:
1. During a dispatched z-run, the dispatcher beats from main every 300 s (sha X), and the agent's worktree autobeat remembers its own sha Y.
2. Every worktree beat after a dispatcher beat pushes with lease Y, which is rejected as "stale info". The beat prints `beat: R0010: ! [rejected] … (stale info)` and retries on X.
3. The agent sees a rejection on stderr every few minutes, while it owns the claim.

The remembered sha catches nothing extra:
- a takeover never writes `hb/<old>`; it deletes it;
- a deletion is caught by either lease, or by the create-only re-read.

Review 013 F3 asked for a pinned silence case for co-beaters, and none was added.
Critique: these are messages that look like a lost claim, given to the agent that must act on "taken over" lines.
Consequences: lease = the sha seen whenever the branch exists. The remembered sha matters only when the branch is absent: then it was deleted, so re-read main before creating (lost, or create). The race proof's generic failure is still said. heartbeat.spec's lease case changes, which is allowed in prep.
Recommendation: adopt that rule. Add a beat.spec case: another terminal's newer commit of the same stamp, then a worktree beat that lands with empty stderr. Add a row: "co-beater rejection".

### F6 [medium] New refusals and drops have no case and no row: `done` refused on a changed stamp, `done` dropping branch, entry and memory, and `--adopt --replace`
Where:
- Readings (2) ("the old lead's `done` is refused by the same stamp check");
- Takeover ("The carried `status <id> prepared` and `./zn done` … refuse");
- When the branch is deleted (`done` "drops the branch, the entry and the memory");
- The lease and ownership (`--adopt --replace`);
- the Rules row "the command that ends a claim drops its branch (give-back, stop; **ready** and done reasoned)", which still names `ready` though `ready` no longer drops anything.

Evidence:
- `grep -n '"done"' acceptance/*.spec.luau` finds no case.
- No spec runs `--replace`.
- `done` is the "task completes" half of the user's "deleted when the heartbeat drops or task completes". Without a case, an implementation that keeps the entry has its next `land` or `commit` recreate the branch while the PR waits.
Recommendation: add lost.spec cases:
- after the stop then ready, the old raft worktree (its memory S1 from `--adopt`) runs `done`, which is refused with "taken over";
- a claim's worktree runs `done`, after which `hb/<stamp>` is gone, the entry and the memory are gone, and the next command there leaves no branch;
- `--adopt --replace` in a worktree that remembers S1 adopts S2 and rewrites the memory.

Add rows for each and drop `ready` from row 209.
Lesson: z-design/spec-design-correspondence

### F7 [low] Leftover wording and edge gaps
- (review 013 F10, still open) `--watch` on a stamp lost before it starts must exit 1 (lost.spec:485), while `stop-restamped` exits 0 (race.spec). Say that the binding check runs before the first tick.
- (review 013 F10, still open) A failed attempt leaves the entry's sha empty, and `remembered or …` treats `""` as a create-only lease against an existing branch. Since every failure is now said, that is a spurious stderr line after each recovery. Say that an empty sha passes `nil`.
- `release <R-id>` ends a rafting claim but is not in the list of commands that drop the branch. The pruner covers it, but say so.
- zz-rules already uses "lost" for a dispatcher run whose supervisor died (Run state, line 178). `./zn lost` and `dispatch status`'s `lost` now mean different things. Name one of them differently, or say how the two relate.
- E8 hooked neither `ready`'s first beat nor the autobeat. `ready` runs in many promoted fixtures (c0120, c0115, ready-members). The Design says so, and Phase 1 owns it. That is honest, and it is noted here only so it is not lost.

Candidate lesson (for the lead; F1): zz-arch, "ownership kept in a checkout cannot tell two processes in that checkout apart: when the taker is sent to the same worktree (`./zn worktree <name>` returns the existing one), the old owner's state is the taker's". Reason: c0265's taker on one host entered the dead agent's prep worktree, its autobeat revived the claim, and a raft taker's `--adopt --replace` made the old session's checks pass. Check: "For each takeover path, which checkout does the taker work in on the same host, and does any automatic effect in that checkout act for the old owner before the takeover?"

Verdict: changes

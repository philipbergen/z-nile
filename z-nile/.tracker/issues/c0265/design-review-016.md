# Review 016: c0265 (design mode)
Inputs: prep head 6eb0d4f7 (`tracker: prep c0265 answer discard round 1 (numbered copy is the taker's)`). This is round 2 of the second restarted count. I read c0265.md, check.sh, design-review-015 and design-refute-015, the diff `1c73a3af..6eb0d4f7`, all five acceptance specs, both proofs and the prototype.
- Unchanged since 1c73a3af: beat.spec, lost.spec, heartbeat.spec, both proofs and the prototype. The diff touched only discard.spec, edge.spec (the co-beater case), check.sh and c0265.md.
- Engine code read: `cmd.worktree`, `worktrees()`, `cmd["worktree-prune"]`, `cmd.busy` with `compact.busyRefNames`/`dirtyWorktrees`, `READ_ONLY`, `rememberClaim`/`claimFile`/`rememberedClaim`, the root `zn` script, dispatcher.luau (`worktree()` 222, the step worktrees 809-815, `streamWorktree` 854, `rafting` 1636), and dispatch.luau `next` (346-382).
- Also read: scripts/hooks/{stop,session-end}.sh, the worktree lines of z-raft, z-run, zz-execute and z-design, and `./zn lessons --when design` / `--skill zz-review`.
- Capture: unchanged since review 015 (`(no capture commit: first add)`, scope judged from #258). The Problem only gained the user's 2026-11-08 line, but its gloss is now wrong (F1).
Dropped from review-015: F1-F4 and F7-F9 (answered as the refute says, checked below). F5, F6 and F10 are partly repeated as F4, F5 and F3.

Replays. All runs were from z-nile, with the prototype copied to `engine/heartbeat.luau` and deleted afterwards; `git status --short` was empty afterwards.
- heartbeat.spec: 21/21 pass. Against the unchanged engine, each fixture spec passes only its setup and fails every other case on an assertion or on the missing command:
  - discard: 1/7
  - edge: 1/6 (the new co-beater case included)
  - beat: 1/11
  - lost: 2/18
  - dispatch: 1/2
  - race: 1/5
- `./zn promote-check c0265`: OK. `bash -n check.sh`: clean. `git hash-object` gives `6fd10bdf…` for proofs/dispatch and `5ae72235…` for proofs/race, equal to the hashes AC4 and AC5 pin.
- Git semantics in a fixture under `.cache/rev016` (deleted after; git 2.54):
  - `git branch -m prep-x prep-x-discarded-1` run from the main checkout renames the branch checked out in `.worktree/prep-x`, and that worktree then shows the new name.
  - The renamed branch keeps the upstream `origin/prep-x` (F8).
  - With the local branch absent, `cmd.worktree`'s existing path (`branch --track` from `origin/prep-x`, then `worktree add`) gives the copy the pushed tip.
  - `git status --porcelain` and `git log origin/prep-x..HEAD` in the old worktree list the dirty file and the unpushed commit.
  - From the discarded worktree, `push.default=simple` refuses a bare `git push`; `push.default=upstream` fast-forwards `origin/prep-x` to the old worker's unpushed commit (F8).

Round-1 answers, checked:
- F1: the numbered copy is the taker's, and `discard.spec` pins the old path and the copy's branch. Correct, but F1 below repeats the stale sentences.
- F2: lost.spec 457-504 passes under "memory is never dropped by the observation":
  - 461: `sync` drops only the entry.
  - 467: memory S1 differs from origin's S2, so the carried move is refused.
  - 472 and 476: the bare beat and `--adopt` both see memory that differs from origin, so both are refused.
- F3: the guard exempts exactly `READ_ONLY`, so `lessons` is refused there.
- F4: busy is now asked about `pickman`, and a correct `busy` names the discarded worktree (`worktree … has uncommitted changes under pickman`). The assertion is too weak, though (F6).
- F7: the unpushed commits fall back to `origin/main` when nothing was pushed.
- F8: the parked, unreadable and claim-less cases kill `--takeover` without `settle`.
- F9: AC6 no longer greps `--from origin/prep-`.
- The guard must run before the autobeat. That ordering is pinned without being stated: if the autobeat ran first, case 5's `lessons` at LATE+5 would beat S1, and case 6's takeover claim would then be refused as alive.

Fixture walk, against a correct implementation of the stated design:
- discard.spec: every case passes. Its mutants are killed:
  - the taker entering the old worktree (case 4's stdout);
  - a new branch name for the taker;
  - the remote rewritten;
  - a copy overwritten (case 7);
  - `settle` ignored (case 3);
  - no fresh marker (case 4's second taker);
  - a command run in the discarded worktree, the beat included (case 5);
  - the work deleted.
  "busy ignoring it" survives (F6).
- edge.spec, co-beater case: the shim replaces `hb/<S73>` just before wt's leased push. The rejection reads `(stale info)` and the retry writes `due` over epoch 7. "Saying every rejection" is killed by the empty-stderr assertion, and "no retry" by `epochs == {due}`.
- beat, lost and both proofs are unchanged and pass as walked in review 015. The memory rules changed under lost.spec, and I re-walked 457-504 (above).

### F1 [medium] The Problem's gloss of the user's 2026-11-08 decision and the Assumptions' "Takeover" bullet still describe the rejected reading, and two readings of the sentence are taken without being listed for veto
Where:
- Problem, the 2026-11-08 `Decided with the user` line: "(a takeover moves the old worker's worktree aside as <name>-<n>, a fresh worktree continues the work…)".
- Assumptions, "Takeover": "in a fresh worktree at the original name, the old worktree being renamed aside (below)".
- The review-count note: "a takeover renames the old worktree and a fresh worktree continues the work".
- Against these, reading (4) says the copy is numbered and the old worktree stays at its path, and Discard and recover says: "The old worktree's local branch is renamed (the "rename the old worktree")".
Evidence: the three sentences contradict reading (4), discard.spec and AC7, so an executor and the user, reading for veto, get two designs. Reading (4) lists only which worktree carries the number. It does not list two other choices:
- **"Rename the old worktree" is carried out as renaming its branch.** The directory keeps its name. The user's verb names the worktree, so this is a reading in its own right, and the strongest reason the design gives (sessions address a checkout by path, review 015 F1) is exactly why it was chosen.
- **"Create a copy" is a new worktree on the pushed branch, not a copy of the old worktree's state.** The old worker's unpushed commits and dirty files stay behind, listed, for the taker to carry over by hand. The user's "I assume that there is a point in trying to recover the work" fits a copy built from the old local HEAD at least as well: `git worktree add -b <branch> <copy> <old HEAD>` brings the unpushed commits along at no cost. The 2026-11-07 "ok" (continue from the pushed branch) predates the user's word "copy".
Critique: the reading is sound. Of the three options review 015 laid out, it is the only one that tells a path-addressed process anything. But "listed for veto" only works if the user sees every choice and no restatement of the old one remains (lesson restated-rules-move-together; the refute answered F1 "fixed" without sweeping these sentences).
Consequences: if the user picks "the copy starts from the old HEAD", the copy's branch diverges from `origin/<branch>`. The PR head then moves only when the taker pushes. The recovery note shrinks to the dirty files, and discard.spec case 4's `HEAD == pushed` changes to `HEAD == the old HEAD`.
Recommendation: rewrite the Problem gloss and the Assumptions bullet to state reading (4). Add both sub-readings to "Readings … for veto", each with its alternative and its cost: the directory is not renamed; the copy starts from the pushed branch, not from the old HEAD. Keep the spec as it is unless the user chooses otherwise.
Lesson: z-design/restated-rules-move-together

### F2 [medium] On the day this lands, no worktree can be told or kept alive the way the Design says: their engines and their claim memory both predate it
Where:
- Assumptions, "Basis of flatline": "their owners run `./zn beat <id>` from their worktree (any later `./zn` command there then keeps it alive)".
- The lease and ownership: "A checkout with no memory … refuses a bare `beat <id>`".
- Discard and recover, step 2 (memory, else `--item`) and the old-process guard.
- Lessons pass: `new-rules-migrate-existing-work`.
Evidence:
1. `./zn` runs the checkout's **own** engine (`zn`: `cd "$top"; exec lune run z-nile/engine/main`). A worktree whose branch was cut before c0265 merged runs an engine with no `beat`, no autobeat, no discard guard and no stamp check. There are many such worktrees now (R0061, R0071, R0083 and about 20 `prep-*` under `.worktree/`). Its owner's `./zn beat <id>` is an unknown command. After a takeover, the old process in the discarded worktree is never told: the user's stated purpose fails for exactly the claims that flatline on landing day. Its carried `status <id> prepared` is published by the old engine, which has no stamp check, so it overwrites the taker's claim (against the user's "refuse").
2. Even after merging main, no existing worktree has `.cache/tracker-stamp-<id>`, because the file is new. A bare `beat <id>` there refuses with "not held by this checkout", so the day-one instruction contradicts the bare-beat rule. `worktree <name> --takeover` refuses those worktrees ("use `--item`"), so `--item` becomes the main path on landing day.
3. `--item <id>` checks only that the named item is lost. It never checks that the worktree belongs to it, so `worktree prep-foo --takeover --item c0010` discards a live worker's checkout on another item. That worker is then told to stop.
4. The memory already exists today under another name. `setStatus` writes `.cache/tracker-claim-<id>` = the claim stamp for issue claims (main.luau 1582; `prep-work-heartbeat/.cache/tracker-claim-f0265` holds `preparing-marble-walrus-walrus`), and c0116 writes it for rafting claims.
Critique: the Design treats day one as "beatless claims read lost". The bigger gap is that the takeover machinery assumes the old worker runs c0265's engine.
Consequences:
- Reading `tracker-claim-<id>` as the memory when `tracker-stamp-<id>` is absent is read-only, so it does not change c0116's meaning for `release` and `fold`. It gives every existing worktree its claims, and so its takeover and its refusals once its engine is current.
- The old-engine case cannot be fixed in the old worktree. It can only be detected: the taker's `--takeover` can test `git -C <old> merge-base --is-ancestor <the c0265 merge> HEAD`, or the guard's presence in the old worktree's `main.luau`, and say "the old process runs an engine without the discard guard: it will not be told; stop it by hand".
Recommendation:
- State the memory fallback.
- Correct the day-one instruction to "`./zn sync` (or merge `origin/main`) in the worktree, then `./zn beat <id> --adopt`". The executor's PR lists the claims and this command.
- Make `--takeover` say when the old worktree's engine predates the guard.
- Refuse `--item <id>` unless the item matches the name (`prep-<its slug>`, its R-id) or the worktree's memory.
- Add discard.spec cases:
  - a worktree with only `tracker-claim-<id>` is taken over without `--item`;
  - `--item` naming an unrelated item is refused, and nothing moves.
- Add a row for each.
Lesson: z-design/new-rules-migrate-existing-work

### F3 [medium] (repeat of review-015 F2, in part) The lease paragraph says both that `--adopt` writes the memory "the main checkout included" and that a main-checkout `--adopt` writes none; the case review 015 asked for is missing
Where: The lease and ownership. First: "`--adopt` … beats origin's stamp and **writes the memory in the adopting checkout, the main checkout included** (the main checkout's list of ignored files it may write gains `.cache/tracker-stamp-<id>`; zz-rules says so)". Later in the same paragraph: "The dispatcher's `--adopt --stamp <S>` and an `--adopt` in the main checkout write no memory". beat.spec is unchanged.
Evidence: memory is never dropped, and main can run no claim-ending command (status changes refuse in the main checkout). So under the first sentence, a main checkout that once adopted X (S1) refuses every later `beat X --adopt` after X is re-claimed (S2): "adoption never overrides a remembered different stamp". The day-one fallback and a human's revive from main then stop working for that item forever. No spec separates the two sentences: every main-checkout adopt in beat, lost and edge targets an item that is not re-claimed before main's next adopt of it. AGENTS.md and zz-rules would also gain a main-checkout file the second sentence says is never written.
Recommendation: delete the first sentence's "the main checkout included" clause and the AGENTS.md/zz-rules list change. Add the beat.spec (or edge.spec) case review 015 F2 recommended: main runs `beat X --adopt` while X holds S1; X is re-claimed (S2); main's `beat X --adopt` then beats S2. Add a Rules row: "a main-checkout adoption writes no memory".
Lesson: z-design/restated-rules-move-together

### F4 [medium] The `.cache/fresh` marker never expires, and the no-worktree path does not write it: one crash wedges the takeover, and two takers can still discard each other
Where: Discard and recover, step 1 (fresh: "written when a takeover created it and removed when it gets claim memory"; "If none exists it just creates `<name>` as `./zn worktree` does"). discard.spec cases 2 and 3 (`prep-fresh`).
Evidence:
- (a) A taker that dies between `--takeover` and its `status <id> preparing` leaves a copy that is fresh forever. This is the crash class the issue is about, and the window is longest for a raft (`--takeover`, `stop`, `ready`, then z-run's `--adopt`). Every later `--takeover` of that name is refused as "fresh". The documented path is blocked, and the skills forbid the undocumented one (plain `./zn worktree`, which would return the copy).
- (b) When the old worktree is absent (removed, or never on this host), the first taker gets a plain `<name>` with no marker. A second taker's `--takeover <name> --item <id>` (no memory there yet) sees the item still lost and discards the first taker's worktree, which is the race review 015 F5 closed for the other path. discard.spec case 3 pins the gap: it expects `--item` from the `prep-fresh` that case 2's `--takeover` created. An implementation that writes the marker there too (the reading of "written when a takeover created it") fails it.
Recommendation:
- Write `.cache/fresh` with its epoch on every worktree `--takeover` creates, the no-worktree path included.
- Treat a marker older than `STALE` as absent, and say so in the refusal (`fresh: a taker started here <n>m ago`).
- Make case 2 create `prep-fresh` with a plain `worktree`, so that case 3 still tests `--item`.
- Add cases:
  - a second `--takeover` of a no-worktree takeover is refused as fresh;
  - a copy whose marker is older than 900 s can be taken over.
- Add a row for each.
Lesson: zz-arch/automatic-effects-have-an-end-and-a-subject-check

### F5 [medium] (repeat of review-015 F6) Routes into the old worker's checkouts remain, because lookup by name cannot find the worktree of a lost item
Where: "Looking a worktree up by name … So every path that asks gets the taker's copy". The `ws-<issue>` streams are "listed and left alone". z-raft: "a lost rafting claim: `./zn worktree raft-<slug> --takeover`". AC6 greps `--takeover` only in z-design and z-run.
Evidence:
- **Streams.** The taker's z-run creates waves with `./zn worktree ws-<issue> --from <raft branch>` (zz-execute 2B step 2). `cmd.worktree` returns the existing `.worktree/ws-<issue>`, which still has branch `ws-<issue>` and is not discarded. The new lead's stream subagent and a waking old one then share that checkout, which was branched from the now-discarded local raft branch, and the old one is never told. `git merge --squash ws-<issue>` merges whatever either one left there.
- **Dispatcher.** `dispatch.next` runs z-run for any active raft (dispatch.luau 379-382: no ownership test) in `worktree(ctx, R0010)`. With no takeover run first, that is the old lead's worktree, still on the raft branch, holding the old memory and entries. The dispatched lead's first `./zn` there runs the autobeat of the old entries and revives the lost claim in the old checkout, which is review 014 F1's shared checkout. The dispatcher also builds `.worktree/raft-{id}` (1636) and `.worktree/ws-{id}` (854) as paths, not by lookup.
- **Rafting.** `raft-<slug>` is "any short slug" the old worker chose. Nothing maps a lost R-id to it, so a taker who guesses another slug gets a fresh worktree: nothing is discarded or listed, and only the stamp check tells the old process.
Critique: this is the second round with a hole in the same mechanism (a lookup by name). The name is the old worker's choice. The claim, which is what was lost, is not reachable from it.
Consequences: a takeover by **id**, `./zn worktree --takeover <id>`, can find the worktree whose memory holds the stamp (the `tracker-stamp-*` or, per F2, `tracker-claim-*` of each `git worktree list` entry), and for a raft its `ws-*` worktrees. It closes the rafting gap and the `--item` misuse, and the dispatcher can call it.
Recommendation:
- Add the id form.
- Make a raft's takeover discard its `ws-<issue>` worktrees the same way (marker, branch renamed `ws-<issue>-discarded-<n>`, listed in the note), so that the new lead's `worktree ws-<issue>` creates a fresh stream.
- Make the dispatcher, before a z-run or z-design step on an item whose verdict is lost, run the takeover or stop with the steps to take it over.
- Add an AC6 grep for `--takeover` in z-raft, and a discard.spec case: a raft with one `ws-` worktree, where after the takeover `./zn worktree ws-<issue> --from <branch>` returns a new path and the old one refuses with the discard notice.
Lesson: z-design/results-land-on-every-path

### F6 [medium] discard.spec's busy assertion, and its recovery-note path assertion, pass when the discarded worktree is ignored
Where: discard.spec 162-163: `has(busy.stdout .. busy.stderr, NAME)` with `NAME = "prep-hello"`. Line 129: `has(r.stderr, NAME)`. Rules row "`./zn busy` names a discarded worktree … | busy ignoring it".
Evidence: `compact.busyRefNames` lists `refs/heads/*` and `refs/remotes/origin/*`, so `busy pickman` prints `branch prep-hello changes pickman` for the copy's own branch and for `origin/prep-hello`, both of which hold `pickman/pushed.txt`. "prep-hello" is a substring of that line, so the assertion holds even when busy skips the discarded worktree and its `prep-hello-discarded-1` branch: the row's mutant survives. In the same way, the note's "names the discarded worktree" is satisfied by any mention of the copy, `…/prep-hello-1`.
Recommendation: assert the exact lines: `worktree {dir(NAME)} has uncommitted changes under pickman` and `branch prep-hello-discarded-1 changes pickman`. Assert that the note contains `dir(NAME)` followed by a delimiter the Design fixes, for example `discarded: <path>\n`.
Lesson: z-design/spec-design-correspondence

### F7 [low] A beat already running when the takeover happens is not stopped by the marker, and between `--takeover` and the taker's claim it can revive the claim
Where: "this covers the beat, the autobeat, `--watch`"; the guard is placed "at the top of the command dispatch" (step 3b); the dispatcher's tick reads "the stamp in the memory of the step's worktree".
Evidence: until the taker claims, `main` still holds S1, which equals the discarded worktree's memory. Two beaters can then revive it:
- A `--watch` loop started before the discard (a suspended session wakes) ticks without passing through dispatch.
- The dispatcher's `--adopt --stamp S1` child runs in the main checkout.
The taker's `status <id> preparing` in the copy is then refused as alive while the copy is fresh, until the loop's bound ends (at most an hour). After the taker claims, both stop on the stamp mismatch.
Recommendation: `--watch` checks `.cache/discarded` at each tick, and the dispatcher checks the marker in `st.worktree` before each beat. Say that this window is the only one.

### F8 [low] The renamed branch keeps its upstream, so a bare `git push` from the discarded worktree can move the PR head
Where: Discard and recover, step 3 (`git branch -m <branch> <branch>-discarded-<n>`).
Evidence (fixture): after the rename, `prep-x-discarded-1` still tracks `origin/prep-x`. With `push.default=upstream` (or `tracking`), a waking process's plain `git push` fast-forwarded `origin/prep-x` to its unpushed commit. Under the default `simple`, git refuses.
Recommendation: run `git branch --unset-upstream <branch>-discarded-<n>` in step 3, and add a line for it to discard.spec case 4 (`for-each-ref --format=%(upstream)` is empty).

### F9 [low] Leftovers
- `heartbeat.nextSuffix`'s `taken` set should also hold the `<branch>-discarded-<n>` branches. Otherwise a leftover discarded branch whose directory was removed makes step 3's `branch -m` fail.
- heartbeat.spec's case title still reads "a discarded worktree is named with the smallest free numeric suffix" (it now names the copy). Its "another name's suffix is not ours" line cannot fail: `prep-x-1` is already in `taken`, so a mutant that counts `prep-xy-1` gives the same answer. Use `{ "prep-xy-1" }` and expect `prep-x-1`.
- Say what `./zn worktree <name>` does when no worktree has the branch checked out and `.worktree/<name>` is a discarded worktree (the copy was removed by hand). Today's code would return it, because the path matches.
- Review 015 F3's consequence is still unstated: in a discarded worktree, the Stop hook's `--affected` gate runs nested `./zn` (`skills --check`), which is refused, so the old session's stop is blocked once. The blocked stop shows the discard notice, which is a useful second telling.
- `release` is missing from the claim-ending commands that end a checkout's memory (review 014 F7 and review 015 F11).
- The dispatcher's step-made-claim stamp row still has no case (review 015 F10). That is acceptable because the step's own autobeat keeps such a claim alive; say so in the row.

Lesson candidates (for the lead):
- zz-arch: "a worktree runs its own engine: a rule meant to stop an old process must say what happens when that process predates the rule". Check: "for every guard or refusal aimed at another checkout's process, which engine version does that process run?"
- z-design: "find a lost claim's checkout by its claim, not by a name its worker chose". Check: "can the taker reach the old checkout from what `./zn lost` prints?"

Verdict: changes

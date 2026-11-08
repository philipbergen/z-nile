# Review 012: c0265 (design mode)
Inputs: prep head 62c8b64e (`tracker: prep c0265 storage method reopened: heartbeat branch hb/<claim stamp> with a force-with-lease takeover`). This is round 1 of the restarted count (the heartbeat-branch design). Files read: c0265.md, check.sh, acceptance/{heartbeat,beat,lost,edge}.spec.luau, proofs/{dispatch,race}.spec.luau, experiments/heartbeat.proto.luau, harvest.md and design-review/refute-001..011 (for history only). Also read: `./zn capture c0265`, `./zn lessons --when design --full`, engine/wrapper.luau (`decidePush`, `GH_ALLOWED`), engine/wrap.luau (the push dry run), bin/git, engine/compact.luau `busyRefNames`, engine/main.luau `setStatus` and engine/status.luau `carriedByPr`, engine/dispatcher.luau (`snapshot`, `tripwire`), tests/lib/fence.luau `snapshot`, .github/workflows/deploy.yml, and the repository rulesets (`gh api …/rulesets/24154428`: `no-force` covers `~DEFAULT_BRANCH` only).
Capture: `./zn capture c0265` prints `(no capture commit: first add)`. The first commit is the user's #258 rename, so it is not a confirmed capture. I judged it from that commit and the item's history. The title, the Problem and the Solution match it, and the only additions are `Decided with the user` lines and one Solution bullet of design detail.
Replays (from z-nile, the prototype copied to `engine/heartbeat.luau` and deleted after; `git status --short` empty): `../zn run --time 900 -- lune run tests/run -- …`: heartbeat 19/19. Against the unchanged engine, beat, lost, edge, dispatch and race pass their setup and then fail on the missing `beat`/`lost` or on assertions (the red state E7 describes). `./zn promote-check c0265`: OK. Eight mutants of the new pure rows (plan lease always `""`, plan going backwards, takeoverPlan delete with no lease, takeoverPlan keeping the old branch, a non-empty create lease, rejected always retrying, rejected treating a missing branch as lost, prune with no lease) each fail heartbeat.spec on one case. The proof hashes match (`cad8d98f…`, `5ae72235…`). `bash -n check.sh`: clean.
Probes (all `./zn run`): (1) In a local bare repository, a stale-lease and a deleted-branch lease give porcelain `!\t…\t[rejected] (stale info)` with `Done` and exit 1, so `wrap.luau`'s "dry run did not finish" never hides a lease rejection under the dispatcher. An atomic push with one stale lease rejects its other refs `(atomic push failed)`. `--force-with-lease=<ref>:` creates only when the ref is absent. (2) On the real origin, a **dry run** of `--atomic --force-with-lease=refs/heads/hb/probe-review: … :refs/heads/hb/probe-review-absent` was accepted (GitHub takes atomic pushes; nothing was written). `ls-remote origin 'refs/heads/hb/*'` is empty before and after, so no hb/probe-review exists to delete.

Walk (a correct implementation of the design as stated):
- edge.spec: the restamp race is refused at publish (`canTakeOver(lost, old, RESTAMP)` is false after the shim moves main). In the beat race, wt's `lessons` drops c0070's entry (restamped in case 1) and beats c0071 with a lease. The shim then moves main and atomically deletes hb/old and creates hb/new. The push is rejected (stale info). `rejected` re-reads main, sees the new stamp and reports "taken over (now preparing-mellow-badger-jolly)". The entry is gone, hb/old stays absent and hb/new carries epoch 1. Three mutants fail here: a push with no lease and a create-only lease both recreate hb/old, and a re-read that skips main returns `create`. Fold makes one branch. All pass.
- beat.spec: walked as in round 11 with branches. In the worktree case at +1000 the lease (whether the entry's sha or the read sha) meets the main checkout's T0+600 commit: rejected, then retried on the sha there, so `mine() == {T0+1000}`. All pass.
- lost.spec: all pass. One check: the old claimant's `sync` must say "taken over", not "claim ended", after the taker's `status c0010 prepared`. That move is carried (`carriedByPr(preparing, prepared)`, never published), so origin still holds the taker's stamp and "taken over" is right.
- proofs: dispatch passes. Its `#seen == 1` can no longer fail (F7). race passes, given F5's distinction between a rejection and a failure.

### F1 [high] `beat` is not bound to the beater's own claim, so an old owner that comes back through `./zn beat` (the `--watch` restart the skills prescribe) or the dispatcher's tick beats the taker's branch and is never told
Where: Design, The engine edge (`./zn beat`: "fetches `origin main` first … refuses an item that is not a claim … pushes `plan`'s write"; "Every `./zn` command **except `beat`** … first reads the worktree's entries"; `--watch` "each tick asks `heartbeat.watch`"); The lease and ownership ("the sha this checkout last wrote for that stamp … or, without one, the sha it just read"); The dispatcher ("every `INTERVAL` it starts `zn beat <id>`"); The skills (z-design: "when it reports its bound, restart it"); Problem, `Decided with the user (2026-11-08)`.
Evidence: `beat <id>` takes the stamp it beats from origin/main at the moment it runs. Three paths follow:
- Agent A's `--watch` hits its hour. Meanwhile B took c0010 over (stamp S2, hb/S1 deleted, hb/S2 created). A restarts the loop, as z-design says. The new loop's start stamp is S2, and S2 has no throttle entry in A's worktree, so the lease is the sha just read from hb/S2. The push succeeds. A keeps B's claim alive and overwrites its entry with `S2 <epoch> <sha>`. From then on its autobeat matches origin's stamp too, so A is never told. The user's sentence is "this would tell the process that it lost the ownership if it comes back around". Here the very command it comes back with adopts the new lease.
- A plain `./zn beat c0010` in A's worktree does the same: `beat` is excluded from the entry check.
- The dispatcher's `zn beat <id>` child, in the main checkout, beats whatever claim holds the item. A dispatched step on an item whose claim belongs to a dead terminal therefore keeps that dead claim live for the whole step. dispatch.spec requires exactly that: c0050 is claimed by the fixture, not by the step.

The lease only catches a takeover that lands between the beat's read and its push, which is about a second (edge.spec's shim).
Critique: ownership is the pair (stamp, branch), but no beat path carries the stamp its holder owns. The tempting fix is to make `beat` read the worktree's entry. That fails in the main checkout (no entries), for the dispatcher, and for a worktree whose entry the beat itself rewrote.
Consequences: a stamp-bound beat needs a source of "my stamp" on every path:
- a worktree: `.cache/tracker-stamp-<id>`, the claim memory this design already writes on every claim publish;
- the dispatcher: the stamp origin holds when the step starts, or the stamp the step's agent recorded;
- a human in the main checkout: an explicit adoption.

Rule changes that follow:
- z-run's re-adopt (F2) must write that memory.
- The `--watch` restart must refuse in a checkout whose memory differs.
- The dispatcher must stop beating, and say so once, when the stamp changes mid-step.
- dispatch.spec (a pinned proof, which prep may still change) has to seed the step's stamp the way the chosen rule reads it.

Recommendation:
- `beat` (explicit, `--watch` and autobeat alike) beats only the stamp this checkout remembers. When origin differs, it refuses with the takeover text (`<id>'s claim was taken over (now <stamp>)` or `claim ended`) and drops the entry, exit 1 for the explicit form, and never rewrites its memory to origin's stamp.
- In a checkout with no memory (the main checkout), `beat <id>` beats origin's stamp only when given it (`beat <id> --stamp <s>`, the dispatcher's form, with the stamp read at step start). A bare `beat <id>` there either refuses or is a stated adoption. Put that choice in the Design.
- Cases:
  - lost.spec, after the takeover: `beat c0010` in wt refuses with "taken over" and `tipOf(taken)` is unchanged;
  - lost.spec: `beat c0010 --watch` under a bound in wt exits at once with "taken over" (or put this in race.spec);
  - a proof case where the item is restamped mid-step and the dispatcher writes no beat for the new stamp.
- Rows and mutants: "beat re-derives its stamp from origin" and "dispatcher beats whatever holds the item".

### F2 [high] Taking over a lost `active` claim (z-run's "re-adopt") keeps the old stamp and branch, so the old owner is never told and the takeover is not recorded
Where: Design, Takeover ("An `active` claim is taken over as today (`./zn stop`, `/z-run`)"); Automatic beats ("A readied raft nobody starts … `/z-run` re-adopts it (its worktree writes the entry)"); The skills ("`z-run` of a lost raft re-adopts it"); Problem: "A worker that takes over lost work does so as a normal claim, and the takeover is recorded (c0263)" and `Decided with the user (2026-11-08)` ("If a job is taken over the take over deletes the heartbeat branch and creates a new one").
Evidence: the Solution names `active-…` on a readied raft as a lease. After a re-adopt by `/z-run`, though, both agents beat hb/<active stamp>. Their leases conflict, then each retries on the sha it finds (`rejected` → `retry`), so both keep beating and neither learns anything. No commit records the takeover, and the stamp never changes, so the old z-run session, back from a sleep, keeps executing the raft beside the new one. Only `./zn stop` plus a new `ready` changes the stamp, and the skills tell the new worker to re-adopt instead.
Critique: the user's takeover semantics (delete the old branch, create a new one, the old owner learns) and the capture's "recorded" outcome are designed only for `preparing` claims. For `active` claims, the outcome has no Design and no criterion.
Consequences: a takeover of an active raft needs a fresh `active-` stamp on the raft and its members (they share it), recorded in the commit subject, the atomic branch swap (`takeoverPlan` already fits) and a stamp memory in the new worktree. Things to check:
- whether `prompt.md`, `./zn stop`, `done` or the raft branch name key on the active stamp (none should break, since `ready` draws a fresh stamp anyway);
- the old lead's carried moves (`done` from the old worktree), which must be refused the way the old `prepared` is;
- a parked raft (an open PR), which must refuse the takeover as for `preparing`.

Recommendation: add an explicit active takeover, for example `./zn status <R-id> active` on a lost readied raft, or a `--take-over` that z-run calls. It needs a lost verdict, a `freshStamp("active")`, the subject `tracker: <R-id> active (takes over <old>)` and `takeoverPlan`. z-run's re-adopt becomes that command. Add lost.spec cases: the lost readied R0010 is taken over (new stamp on R0010 and c0040, subject recorded, hb/old gone and hb/new present), the old worktree's next command says "taken over", and a parked raft is refused. Name the active case in AC3. If the user meant re-adopt to keep the stamp, escalate to the user: keep the stamp (the old owner is never told) or swap it (the cost above).

### F3 [medium] "The branch is deleted when the claim ends, is given back" has no mechanism and no criterion: only another checkout's later beat prunes it
Where: Solution ("The branch is deleted when the heartbeat drops (the claim ends, is given back, or is long unclaimed)"); The beat, Plan ("deletes the branches of stamps no claim holds only when older than `STALE`"); Problem, `Decided with the user (2026-11-08)` ("a heartbeat branch that gets deleted when the heartbeat drops or task completes"); lost.spec "an entry for a claim that merely ended" (it never looks at the branch).
Evidence: no command deletes a branch:
- `status <id> new` (give-back), `./zn stop` and `ready`, which restamps a rafting claim `preparing-…` to `active-…` and leaves hb/<preparing stamp>;
- `done`, and the PR merge that ends the carried `prepared`.

A branch goes away only when some later claim's beat runs `plan` with the ended stamp unclaimed and older than 900 s. In a quiet repository (one worker who finished), the branches stay on origin and in GitHub's branch list indefinitely.
Critique: this is the user's completion half of the idea, and the Solution says it is done. The fix that suggests itself is "delete in every release command". But the PR merge happens on GitHub, where no `./zn` command runs.
Consequences: explicit deletes (each with a lease on the sha seen, best effort, said on failure, like the first beat) in `status <id> new`, `stop`, `ready` (the rafting branch, in the same push as its first beat) and `done`, and pruning kept as the backstop for merges. In a raft, `done` runs before the merge, while the claim is still active on main. Deleting there would make the claim flatline from its landing time, but the open PR parks it, so nothing reads lost.
Recommendation: state which commands delete and that pruning covers the merge, and keep "deleted when the heartbeat drops" (a lost claim's branch is kept until the takeover) as a stated reading. Cases in beat.spec and lost.spec: after `ready R0010` the rafting branch is gone (a fixture raft claimed by `new raft` first); after `status c0070 new` hb/<its stamp> is gone. Add a row with the mutant "branch left for the pruner".

### F4 [medium] The lease rule is stated two ways, the throttle entry has two formats, and "it can never recreate it" holds only for one of them; no case tells them apart
Where: The lease and ownership ("`<sha>` is the sha this checkout last wrote … (its throttle entry remembers it) or, without one, the sha it just read"; "it can never recreate it"); `heartbeat.plan` (prototype: `lease = existing.sha` or `""`); The engine edge (`beat` writes "`<stamp> <epoch> <sha>`"); Automatic beats ("`.cache/tracker-beats/<id>` … (`<stamp> <epoch>`, ignored)"); Rules row "a beat replaces the claim's branch with a lease on the sha seen".
Evidence: a beat fetches main, then fetches the hb branches. A takeover lands between the two (main moved, then hb/old deleted and hb/new created). The beat then sees its old stamp on main and no branch. `plan` gives `lease = ""` (create only), and the push recreates hb/old. In the main checkout and in the dispatcher (no entries), that is the rule as written. In a worktree, the Lease paragraph's entry-sha lease would reject it, but `plan` cannot express that lease and no spec pins it. edge.spec's shim fires at the push, after both reads, so the read-sha lease and the entry-sha lease both pass it. The recreated hb/old outlives the beat until pruning. The old owner is told only at its next command.
Critique: the one-reader rule (zz-arch) and `restated-rules-move-together`: the pure module and the prose disagree on what the lease is.
Consequences: whichever rule wins, one gap remains. A create-only beat (branch absent) can still race a takeover in any checkout that has no remembered sha.
Recommendation:
- One rule, in the pure module: `plan(stamp, epoch, beats, claimed, now, remembered: string?)`. The lease is `remembered` when this checkout last wrote the branch, else the sha seen, else `""`.
- One entry format, `<stamp> <epoch> <sha>`, with the sha empty after a failed attempt.
- After any create-only write, the beat re-reads main and, if the stamp changed, deletes what it created with its lease and reports the loss.
- Cases:
  - heartbeat.spec: `plan` with `remembered` and no branch seen gives the remembered lease;
  - edge.spec: a shim armed on the `fetch … hb-seen` read performs the takeover between the two reads, and hb/old must stay absent and the loss be said.

### F5 [medium] The Design never says how a beat tells a lease rejection from any other push failure, and race.spec's failed-tick proof depends on it
Where: The engine edge ("on a rejection it calls `heartbeat.rejected`"; `--watch`: "a failed tick relays git's stderr (`beat: <id>: <git's message>`) and the loop retries at the next tick"); proofs/race.spec "beat --watch says a failed tick" (`has(r.stderr, "fake beat push failure")`).
Evidence: the shim's `pushfail` exits 1 with `fatal: fake beat push failure` and no porcelain line. Suppose an implementation treats every failed push as a rejection. It re-reads, gets `retry`, and the retry succeeds (the marker is gone). The tick then reads as a success, and the message may never be relayed, so the pinned proof fails for an implementation the text allows. A rejection also has two spellings, `(stale info)` and, in an atomic push whose prune target vanished, `(atomic push failed)` on the other refs (probe 1). A beat whose only problem is a co-beater's earlier prune is therefore "rejected" too.
Critique: `plan` puts the prune deletions and the write in one atomic push, so every vanished prune target fails the beat.
Consequences: classifying from `--porcelain` (`!` lines) is reliable, because the wrapper's dry run passes porcelain through (probe 1). Pushing prunes separately from the write, or non-atomically, stops a prune race from rejecting the beat.
Recommendation: state that a beat pushes with `--porcelain`. A `!` line with `stale info` on the claim's own ref is a rejection (→ `rejected`). Anything else is a failure: relayed, the entry advanced, no retry inside the tick. Prune deletions go in a second, non-atomic push, or the beat retries without them. Add a heartbeat.spec or edge.spec case where a prune target vanished before the push and the beat still lands.

### F6 [medium] `Overrides: none` rests on E8, which ran the refs design's first beat; the branch design adds a commit object and a remote branch to every fixture claim, and no suite run covers it
Where: Regression guard (`Overrides: none`); E8 ("pushed the first beat (`git push -q origin refs/remotes/origin/main:refs/zn/hb/<stamp>/<now>` …)"); Implementation step 1.
Evidence: every claim, `ready`, `new raft`, `fold`, `unfold` and `recombine` in every promoted fixture now runs `git commit-tree`, fetches `+refs/heads/hb/*:refs/zn/hb-seen/*` and pushes `refs/heads/hb/<stamp>`. Fixture origins gain branches, and plain fetches in fixtures gain `origin/hb/*` tracking refs. Specs that list origin's branches or run `busy` or compaction (tooling/busy-holds-move, c0115/c0120 freeze, c0114 compact-roots, c0005 worktree, c0117 control-cli) were never run with that. E8's 265/265 used a push of an existing commit to a non-branch ref.
Critique: lesson `confirm-overrides-with-a-suite-run`. The grep I ran is not proof either.
Consequences: a red spec found at execution becomes an unnamed override, which is a stop condition.
Recommendation: rerun E8's scratch engine with the branch-shaped first beat (commit-tree, the hb fetch, the branch push) against the whole z-nile suite. At minimum, run c0116, c0053, c0117, c0115, c0120, c0114, c0005 and tooling/busy*. Record the counts and the gate's added time in E8, and name any red spec in Overrides.
Lesson: z-design/confirm-overrides-with-a-suite-run

### F7 [low] Text and records left over from the ref design
Where:
- AC1 (both copies): "a new beat deletes only the older beats of its stamp". A stamp now has one branch and no older beats.
- beat.spec: its title "a beat is a ref outside main", and its shim comment "(fetch, ls-remote, push)".
- lost.spec:316: "no ls-remote".
- dispatch.spec: "keeps one ref", `t.expect(#seen).toBe(1)`. The `for-each-ref` call names one exact ref, so this assertion cannot fail.
- Rules row: "beat :: beat pushes a ref from the main checkout too" (the case is now "pushes a branch").
- E5: "17 of 17 … 15 mutants". The spec has 19 cases, and the new pure rows (plan lease, takeoverPlan, rejected) are marked `run` with no record. I ran eight of them and all were killed (Inputs): record them.
Recommendation: reword these, drop the vacuous assertion (or count every branch under `refs/heads/hb/`), and update E5. dispatch.spec is pinned, so its hash moves in check.sh with it.

### F8 [low] The alternatives table misstates two facts (its conclusions stand)
Where: the method table, "PR label, PR title timestamp or PR comment" row ("a label or title edit is a `gh` write the wrapper refuses"), and the "repo variables / commit statuses / git notes" row ("need permissions the wrapper refuses").
Evidence: `wrapper.GH_ALLOWED.pr.edit = true`, so `gh pr edit --add-label/--title` passes the wrapper. A notes push is a `git push` to `refs/notes/*`, which `decidePush` passes (only main is judged). The real reasons are the ones the table also gives: no PR before a prep claim, no conditional edit (lease), and for notes one shared ref that every beater contends for.
Recommendation: correct the two cells so the user's own options are rejected on true grounds.

### F9 [low] Every checkout writes and prunes one shared `refs/zn/hb-seen/*`
Where: The beat, Name ("one `git fetch -q --prune origin '+refs/heads/hb/*:refs/zn/hb-seen/*'`").
Evidence: worktrees share refs. Two `./zn` commands at once (two worktrees' autobeats, the dispatcher's child, `refreshBoard`) fetch into the same refs. One can fail on a ref lock, which reads as "heartbeats unreadable" and costs a missed beat or refuses a takeover. A `--prune` from one can remove a ref another is about to read. It fails safe. c0117 met the same thing and gave each wrapper call a private ref (`refs/zn-wrap/<uuid>/main`, review 005 F1).
Recommendation: fetch into `refs/zn/hb-seen/<uuid>/*` per call and delete it after, or record the shared namespace as an accepted cost.

### F10 [low] A Rules row lists a mutant no case can kill
Where: Rules row "a beat racing a takeover is rejected by its lease…": mutant "a lease of the wrong sha".
Evidence: a wrong lease is rejected on every beat, `rejected` then retries on the sha it finds, and every case's outcome is unchanged. In the race the wrong lease is rejected too, which is the expected result there.
Recommendation: drop that mutant, or name what would observe it (a push count).
Lesson: z-design/reasoned-rows-claim-testable-reasons

Candidate lesson (for the lead to write; F1, F2): zz-arch or z-design, "a lease renewal takes the lease id from its holder's own record, never from the shared state it renews". Reason: c0265's `beat` re-read the claim stamp from origin, so a returning or foreign beater adopted whoever held the claim, and an `active` re-adopt kept the old id. Check: "For each path that renews or extends a lease (an explicit command, a loop restart, a supervisor's tick, a re-adopt), where does it get the id it renews, and does it refuse when that differs from what the holder recorded?"

Verdict: changes

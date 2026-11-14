# Review 001: c0274 (design mode)
Inputs: the prep worktree `.worktree/prep-take-over-lost-claim` at e63526f2 with its uncommitted prep files: c0274.md (`git hash-object` 4b41e735), check.sh (c4381f3f), acceptance/plan.spec.luau (8bdb8a4d), memory.spec.luau (3521017b), takeover.spec.luau (4f57fa99), experiments/e1.sh, envelope.patch (aa709f83), variantA.patch (46edd130) and variantB.patch (a239535b), the last three matching E2's hashes. Prototype `origin/proto-c0274` at 79c52c2e (`git diff bf5aa3c3 origin/proto-c0274`, read whole: heartbeat.luau, main.luau, the skills, README, cachepaths.luau). c0265's prepared design and check.sh from `origin/prep-work-heartbeat` (28e2c906), the split hand-offs `experiments/split/c0275`, `c0276` and `c0277/design.md`, c0265's edge.spec. `./zn capture c0274`, `./zn capture c0277`, c0263.md, z-stop's SKILL.md, `./zn lessons --skill zz-review`, `./zn lessons --when design`.
Capture: confirmed (8577a496). The "next worker resumes it" and "taken over as a normal claim, recorded" outcomes have a Design and AC3; "its late moves are refused" is narrowed (F2); the branch-handling decision has no criterion (F7).
Runs: one probe spec in a scratch clone of `origin/proto-c0274` (its origin repointed to a scratch bare clone, under my scratchpad, never the real repository), `./zn run --time 420 -- bash -c 'cd <clone>/z-nile && lune run tests/run -- tests/acceptance/c0274p/probe.spec.luau'`: 4 passed, and the printed outputs are quoted under F1, F2 and F3. The main checkout and the prep worktree are unchanged. `git ls-remote origin 'refs/heads/hb/*'` is empty, so E1 left nothing behind.
Not findings: repository safety (every spec writes only its `.cache/c0274-*` fixture, and the shims' commits are `@example.invalid` and go to fixture origins); bounded commands (E1 and E2 ran under `./zn run`); the one new line in `z-nile/tests/lib/cachepaths.luau` (`return \`.cache/tracker-stamp-{id}\``, written through `sh.writeReplacing` in `rememberStamp`), which I have read and accept as the reviewer the list asks for. The run rows I checked by reading (P3, P4, P5, P6, P8, P9, E2, E5, E6, E7, E10, E12 to E20, E29) each have a case that fails. E9 is killed by the raft case's `memory(wt2, raftId)`, not by the carried move E4 names, because `rememberClaim` still remembers an issue's takeover. That is a record slip, not a survivor.

### F1 [high] A raft its own owner stops and re-readies can never be finished in its worktree: `beat --adopt` and `done` refuse it as "taken over", and nothing ends the lead's memory
Where: c0274.md Design, "The claim memory" ("`stop` drops the raft's"), "Telling the old owner" (`done`), The skills (z-run step 4 and zz-execute 2b adopt in the raft's worktree); prototype main.luau:1797 (an adoption refused on `taken`), :4753 (`done`), :5463 and :5543 (`stop` passes `mainCheckoutGuards`, so its `dropStamp` runs only in the main checkout, which never holds memory); z-stop SKILL.md step 4 ("To keep them, run `start` on that branch in its worktree").
Evidence: In the probe, wt adopts R0010 as the new z-run step 4 says. The main checkout runs `stop R0010` and then `ready R0010`: the owner's own z-stop and z-ready, not a takeover. Back in wt, `beat R0010 --adopt` exits 1 with `R0010's claim was taken over (now active-silver-badger-silver)`, and `done R0010` exits 1 with `R0010's claim was taken over (now active-silver-badger-silver): this checkout's work is no longer the claim's; stop here (./zn lost lists lost work to pick up)`. z-run step 3 (`cd "$(./zn worktree R0010)"`) returns that same worktree ("a reused worktree may be behind", zz-execute Phase 0), so the documented "keep them" path of z-stop step 4 always lands here, and its raft can never pass `done`. A taker of a lost readied raft on one host lands there too: this issue's z-run text sends it to "its fresh worktree", but in this layer nothing makes one, and the lookup returns the old lead's worktree, whose memory refuses the taker's adoption.
Critique: The Design says the memory ends with "a claim-ending command run in it (... `stop` drops the raft's)", but `stop` refuses to run anywhere except the main checkout, so that drop is dead code. A readied raft's memory comes only from `--adopt`, and an adoption never overrides a remembered stamp that differs. An owner's stop-then-ready and a takeover's stop-then-ready are the same two commands, so the engine cannot tell them apart. The tempting fixes reopen the hole that the user's "refuse" closed: letting `--adopt` override when main shows a newer `active-` stamp, or having `ready` clear the memories of the host's worktrees, would also let the old lead's adoption and `done` through after a real takeover.
Consequences: Any fix needs an act that only the owner makes and that the old process is never told to make. The refusal text must not name it, the rule "never dropped by the observation" stays, and the takeover path stays c0277's numbered copy. The chosen act is a new instruction in z-stop step 4 and z-run, and possibly a new flag in the usage line and zz-rules' command row.
Recommendation: Choose one, and escalate to the user if the choice is not plain:
- (a) An explicit re-adoption form, for example `./zn beat <R> --adopt --replace <old stamp>`, accepted only when the worktree remembers exactly that stamp and main shows an `active-` claim for R. It is written in z-stop step 4 and z-run, never in a refusal.
- (b) z-stop's "keep them" path always continues in a fresh worktree (a numbered copy), never in the old one.
- (c) z-stop step 4 tells the human to delete `.cache/tracker-stamp-<R>` in the worktree they keep.

Whichever is chosen:
- Correct the Design's sentence about `stop` ending the memory (it cannot).
- Add a case: an owner adopts, then stop, ready and the chosen form, after which `done` passes its stamp check and a plain `--adopt` still refuses.
- Add a Rules row with its mutant, and an AC4 phrase for the skill text.
- Say in the layer rule what c0277 must keep of it.

### F2 [high] The old owner's late give-back is not refused: `status <id> new` from the old worktree ends the taker's live claim, and the taker's own carried move is then refused
Where: c0274.md Problem ("The old owner learns it lost the claim if it comes back, and its late moves are refused"); Design, "Telling the old owner" (only the carried `prepared`, `done` and the beats are refused); prototype main.luau:1969-1976 (the stamp check runs only `if carried`).
Evidence: In the probe, wt claims c0010 and wt2 takes it over at AT, which is recorded in the subject. wt, the old owner, then runs `status c0010 new`: it exits 0 and origin shows `new-jolly-brisk-mellow`. The taker's `status c0010 prepared` then fails with `c0010 is new on origin/main: cannot move to prepared`. The old owner's memory read `taken` throughout, which is the very test the carried move uses. A rafting claim's old owner can do the same with `status <R-id> new`. z-design tells a worker to give a claim back with `./zn status <id> new`, so a session that wakes up and abandons its prep does exactly this.
Critique: The capture says the old owner's late moves are refused. The Design narrows that to the carried move, `done` and the beat forms, with no `Scope decision` line. The give-back is the late move with the worst effect: it ends someone else's live claim, and under c0275 it also drops the taker's heartbeat branch. The tempting answer, zz-rules' "Whose claim" (give-backs are open to anyone: "ownership is documented, not checked"), is an inherited rule that disagrees with the captured "refused". That disagreement is the user's to settle; the design should not settle it silently.
Consequences: Refusing by the memory (`holds(memory, origin) == "taken"`) stops only a checkout that has proof it lost the claim. A checkout with no memory, such as another terminal or a human's checkout, still gives back as today, so "documented, not checked" still holds for everyone else. The refusal keeps the memory, and c0275's branch drop at `status new` never runs for the refused move.
Recommendation:
- Refuse every published move of the item from a checkout whose memory reads `taken`, before the publish and with the takeover text: `status <id> new`, `status <R-id> new`, and any other `status <id> <to>` that is not itself a takeover.
- Add takeover.spec cases: the old owner's `status c0010 new` and `status <R> new` are refused, the stamps stay unchanged and the memory is kept. Run them in old-owner worktrees, as the layer rule asks, and pin only the prefix.
- Add a Rules row with the mutant "only carried moves are checked".

If the author reads "Whose claim" as the rule that governs, escalate to the user: keep the captured "refused" for give-backs (this recommendation), or record a `Decided with the user` line that the old owner's give-back stays open.
Lesson: z-design/inherited-decisions-agree

### F3 [medium] A member of a lost rafting claim can be taken over alone, which splits the raft, deletes the branch it shares and leaves the raft impossible to take over; a member under another stamp blocks the raft's takeover with no reason
Where: Design, "The takeover" ("its members that hold the old stamp following"); this issue's z-design line ("A lost prep is taken over by the same claim, `./zn status <id> preparing`"); prototype main.luau:2008-2031 (members follow only the old stamp), :2037 (the "in a raft" refusal reads `raft:` on origin, which is empty for members of a `new raft`), :2089-2097 (`canClaim` refuses a stored stamp), :2746-2752 (`release`: a rafting worktree holds member claims under their own stamps).
Evidence: In the probe, wt3 runs `new raft chore lostraft c0030`; c0030 carries the raft's stamp, and its `raft:` line exists only on wt3's branch. At AT, wt4's `status c0030 preparing` exits 0: c0030 becomes `preparing-otter-quiet-silver` while the raft stays `preparing-sunny-plucky-indigo`. wt4's `status <R> preparing` then exits 1 with `c0030 is preparing on origin/main: cannot move to preparing`. `./zn lost` gives each member of a raft its own line (c0265), and the z-design text this issue adds tells a worker to take a lost prep with `status <id> preparing`, so a z-design session will take this path. The member's swap also deletes `hb/<raft stamp>`, the branch it shared with the raft. Separately, c0116's `release` shows that a rafting worktree may hold a member it claimed with `status <id> preparing` under its own stamp. When that worktree dies, the raft's takeover is refused at that member with the same unexplained line.
Critique: The capture says "a lost rafting claim ..., its members following". A member's own takeover is not addressed, and no spec seeds it. The tempting fix, refusing any issue whose stamp a raft holds, must find that raft by the stamp, not by `raft:` on origin, which members of a `new raft` lack.
Consequences: A refused member takeover must name the raft and the command to use instead. The raft's takeover must then decide what to do with a member whose own claim, under another stamp, is also lost: take it in the same commit, with its old branch in the same atomic swap (several deletes), or refuse, naming the member and its verdict.
Recommendation:
- Refuse a takeover of an item whose stamp a raft on origin also holds, with `c0030 holds R0011's claim: take it over with ./zn status R0011 preparing`.
- For a member under another stamp, either carry it along when its own verdict is lost, with every old branch in the one atomic push, or refuse with that member's verdict.
- Seed both in takeover.spec, in worktrees that run nothing afterwards, with Rules rows. Mutants: the member check dropped; members under another stamp ignored.
- Say in z-design that a member of a lost rafting claim is taken over through its raft.

### F4 [medium] The old claimant's carried-move case pins `c0010's claim was taken over` in a worktree that holds two taken-over claims, so variant B passes only by directory order
Where: takeover.spec:291-295 (c0010, the full id) and :316-320 (the raft, the prefix only); c0274.md E2, finding (3); variantB.patch, `envelopeHeld` (in `fs.readDir(".cache")` order, it names the first item whose stamp differs).
Evidence: When `wt` runs `status c0010 prepared`, its `.cache` holds memories for c0010 and for the rafting claim, and both have been taken over by then. Variant B refuses with `this worktree was discarded: <the first id readDir returns>'s claim was taken over`, so the assertion passes only when c0010 is listed first. E2 (3) says "the carried-move assertions pin the prefix", but this one pins the id. The order of `readdir` is the filesystem's: APFS here, and another filesystem may list `tracker-stamp-R0011` first. The Design says these cases hold under B.
Critique: An upper layer that the layer rule allows, such as a stamp-mismatch guard that names the first item it meets, would turn this sequestered case red on some hosts and not others.
Consequences: none beyond the fixture.
Recommendation: Give the old rafting claimant a worktree of its own: a fifth worktree runs `new raft` in setup, and later runs only the refused `status <R> prepared`. Every old-owner worktree then holds one taken claim, and the id can stay pinned. Rerun the three files on B.

### F5 [medium] AC3's "nothing moves" is not checked: the refusal case's assertions are vacuous, and the old lead's `done` after a stop with no re-ready (`ended`) has no case
Where: takeover.spec:232-234 and :332; AC3 ("refused with the reason and nothing moves", "a claim restamped between the verdict and the publish is refused"); the `done` row of the Rules table; prototype main.luau:4757.
Evidence:
- `t.expect(stampOf(`{P}/c0020/c0020.md`) == parked.stdout).toBe(false)` compares a stamp with the refused command's stdout, which is empty, so it is always false.
- c0010 is checked only for the prefix `preparing-`, which a restamped c0010 also has.
- In the race case, `tipOf(RESTAMP) == ""` checks a branch nobody creates, since the race shim beats nothing; the loser's own branch would be `hb/<its fresh stamp>`.

An implementation that publishes the takeover and then prints a refusal passes all three. Separately, `done` reaches its `ended` branch when the old lead's worktree still has the raft in `active/` locally while origin shows it stopped. Dropping `ended` from `done`, a plausible mutant, survives every case.
Critique: AC3 claims more than the spec checks.
Consequences: Branch counts must stay relative, because c0275 beats on claim paths. Comparing branch names around a refused command is safe, because nothing is published.
Recommendation:
- Before the refused attempts, record the stamps of c0010, c0020 and c0050 and the subject of the last commit touching each, and assert afterwards that they are unchanged.
- In the race case, assert that the set of `hb/` branch names is the same before and after the refused takeover.
- Add a case where the old lead's `done` is refused with `R0010's claim ended` after `stop` with no `ready`, and a Rules row with the mutant "done refuses only on taken".

### F6 [medium] The memory has no end when a claim completes, and the Design disagrees with c0275's hand-off about `done`
Where: Design, "The claim memory" (it ends at `status new`, `release` and `stop`); c0275's hand-off ("it ends only with its checkout ... or by a claim-ending command run in that checkout (`status <id> new`, `release`, `stop`, `done`)"); prototype main.luau:2154-2158 (the carried `prepared` keeps it), `cmd.done` (keeps it).
Evidence: A prep's carried `status <id> prepared` keeps `tracker-stamp-<id>` at `preparing-S`. That is right while main still shows S, but nothing ends the memory after the prep lands, and `done` never drops a raft's. z-raft's own example reuses one rafting worktree (`raft-backlog`), and `./zn worktree prep-<slug>` reuses a prep worktree, so these worktrees collect memories. When one of their items becomes a claim again, for example readied (`active-…`), `holds` reads it as `taken` ("taken over (now active-…)"). Under the layer rule, c0275 beats and tells by the memory at every command, and c0277's lookup skips "a worktree whose remembered stamp differs from main's".
Critique: Maintainability says the siblings "add to these, never a second memory", so this layer must say what the memory of a completed claim means. Otherwise each sibling invents its own reading, and a finished worktree is told it was taken over.
Consequences: Dropping the memory at the carried move would let a second carried move (after another review round) pass as `unheld` even after a takeover. So either the drop waits for the end that main shows, or readers tell "ended normally" from "taken".
Recommendation:
- State the lifecycle: `done` drops the raft's memory, as c0275's hand-off says.
- Say when a completed prep's memory ends. Either a command in that checkout may drop it once main shows the item non-claim, or readers treat a memory whose item has not been a claim since that stamp (one `git log -S`) as ended and stay silent.
- Put the rule in the layer rule, and add a memory.spec case for `done` (and for the landed prep, if that option is chosen).

### F7 [medium] The captured branch-handling decision has no criterion, and its rafting-claim and readied-raft halves have no Design
Where: Problem, `Decided with the user (2026-11-07): "ok" (takeover branch handling: a taker continues from the old agent's pushed branch where one exists, else starts fresh; a lost rafting claim the same way, members following)`; The skills (only z-design's line says to continue from `origin/prep-<slug>`); this issue's z-raft and z-run lines (no continuation); AC4 (pins only `lost prep`, `lost rafting claim`, `lost raft`).
Evidence: `./zn capture c0274` carries this decision in c0274's own Problem. The Non-goal "The worktree a taker works in ...: c0277" names the worktree, not the branch to continue. c0277's capture speaks of a numbered copy and of recovering the old worker's files, not of a taker that runs `status <id> preparing`. A z-design, z-raft or z-run text with no continuation sentence still passes AC4.
Critique: This is rule 11: a captured outcome with no acceptance criterion and, for two of its three kinds, no Design.
Consequences: For a readied raft, continuing means z-stop step 4's "keep them" (the raft branch and its open PR), which meets F1's refusal.
Recommendation:
- Write the continuation for each kind in z-design, z-raft and z-run: a prep continues from `origin/prep-<slug>`; a rafting claim from the branch the old rafting worktree pushed; a readied raft from the raft branch and its PR.
- Pin a phrase of each in AC4.

If the author holds the mechanism to be c0277's, escalate to the user to move the decision there with a `Scope decision` line, and add the Non-goal sentence.

### F8 [low] The taker of a lost rafting claim cannot fold, unfold or release it, and a sequestered case pins the release refusal
Where: Design, "The takeover" (a raft's takeover writes no c0116 claim file); takeover.spec:271-275; prototype main.luau:2371-2387 (`fold` resumes only when `rememberedClaim` equals origin's stamp) and :2721-2726 (`release`).
Evidence: After a raft takeover the taker has no `tracker-claim-<R>`. `fold <R> <id>` is then refused with `<R> is preparing on origin/main: fold takes a prepared raft (or one this checkout claimed)`, and `release` needs `--force`, which the spec asserts. The old owner's claim file names the old stamp, so writing the taker's file would not let the old owner release the raft.
Critique: For "the next worker resumes it" and "a lost rafting claim the same way", the taker resumes a raft it cannot change, and the sequestered pin stops anyone fixing that during execution.
Consequences: A raft takeover that writes the claim file makes the taker its c0116 owner. A non-lost `status <R> preparing` (c0053) keeps today's behaviour.
Recommendation: Write the claim file on a rafting takeover, and assert that the taker's `release` (or a `fold`) works while the old owner's is refused. Or keep the limit, say in z-raft that the taker uses `release --force` and cannot fold, and drop the pin.

### F9 [low] A failed merge after a successful takeover publish skips the memory and the swap, without saying so
Where: prototype main.luau:2160 (`mergeOrigin` exits on failure) before :2171 (`rememberStamp`) and :2178 (`swapBranches`).
Evidence: `published, but merging origin/main failed (merge aborted) ... resolve it with: git merge origin/main`. The claim is on main, but the checkout remembers nothing, so its bare beat is refused with "does not hold", and the old branch is never swapped. The message mentions neither.
Critique: "Every claim publish remembers its stamp" has a failure path that breaks it.
Consequences: none; both steps depend only on the published value.
Recommendation: Run `rememberStamp` and the swap right after the publish, before `mergeOrigin`, and add a Rules row.

### F10 [low] Refusal texts, the usage grammar and AC4's pins
Where: heartbeat.luau:312 (prototype); main.luau:53 and zz-rules' command row; check.sh AC4.
Evidence:
- `takeoverRefusal` prints the default reason "the claim is not judged (not a stamped claim)" for a stamped claim that was simply not judged. That happens when the item became a claim after the judge (an ordinary claim race, where the loser used to get c0053's text alone) or when `beatPaths()` gave nil.
- The usage line and zz-rules' row say `[--adopt --stamp S]`, which reads as both or neither, while `--adopt` alone is the form z-run uses; the engine's own error message says `[--adopt [--stamp <stamp>]]`.
- AC4's `g "--adopt" main.luau` cannot fail, because the flag's code contains the string, so "`--adopt` in the usage line" is not checked. zz-execute's adoption line is not pinned, though the Design says "AC4 pins each by phrase".

Recommendation:
- Use a reason that matches the cause: "claimed since it was judged" or "origin/main's project roots unreadable".
- Write `[--adopt [--stamp S]]` in the usage line and in zz-rules.
- Grep a usage-line phrase (`beat <id> [--watch] [--adopt`), and pin zz-execute's adoption line.

### F11 [low] Rules and records left unstated
Where: Design, "The takeover", "Telling the old owner", "The branch swap"; Implementation steps, step 2.
Evidence:
- A beat that lands between the verdict and the publish does not save the claim: the publish is the lock, and the swap's retry deliberately overrides such a beat. That is a rule, and it is unstated.
- `done`'s stamp check is skipped when origin cannot be read, so it fails open, and nothing says why that is safe.
- The memory is keyed by id and does not follow `compact` or `renumber`, which c0265 lists as moves that keep the stamp.
- Step 2 says "rebase it on the landed c0265", but c0265 never lands alone: it is the raft branch after layer 1.
- The swap writes the taker's branch create-only, so the result depends on c0275 running its first beat after the swap. With the sha seen as the write's lease when `hb/<new>` already exists (it is the taker's own stamp), the order would not matter, and plan.spec's case would still hold.

Recommendation: State each, or fix the cheap ones: the swap's lease, the wording of step 2, and a sentence on `done`'s fail-open and on compaction.

Verdict: changes

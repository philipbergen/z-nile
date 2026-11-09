# Review 002: c0274 (design mode)
Inputs: the prep worktree `.worktree/prep-take-over-lost-claim` at e63526f2 with its uncommitted prep files: c0274.md (`git hash-object` f6f8fea6), check.sh (08051057), acceptance/plan.spec.luau (94623276), memory.spec.luau (3521017b), takeover.spec.luau (6f1f1658), experiments/envelope.patch (279a655f), variantA.patch (80b2e4a9) and variantB.patch (28d848e7), which match E2's hashes, e1.sh, design-refute-001.md (87e3ad64), harvest.md (d9f37203) and the two new lessons it names. Prototype `origin/proto-c0274` at 8f4b9839 (`git diff bf5aa3c3 origin/proto-c0274`, read whole), with `cmd.stop`, `cmd.done`, `cmd.start`, `cmd.release`, `cmd.fold`, `cmd.unfold`, `cmd.recombine` and `new raft` read around it. c0265's c0265.md and spec files from `origin/prep-work-heartbeat` (28e2c906), and its split hand-offs `experiments/split/c0275`, `c0276` and `c0277/design.md`. `./zn capture c0274`, `./zn lessons --skill zz-review --full`, the z-design lessons this design names.
Dropped from design-review-001: none. Its answers hold for F4, F5, F7, F8, F9 and F10 (re-run below). F1's fix opens F1 and F2 here, F2's fix misses `release` (F4), F3's fix misses a recombine's other raft (F3), F6's fix leaves a raft's give-back remembered (F5), and F11's swap lease is repeated as F8.
Capture: confirmed (8577a496). Title, Problem and Non-goals are the captured text plus decision lines, and every captured outcome has a Design and a Checked criterion. The readied-raft half of "the takeover is recorded" is weak (F1).
Runs: a scratch bare clone of this repository and a clone of it at `origin/proto-c0274`, both under my scratchpad (the clone's origin is the scratch bare), with the issue's three spec files and c0265's four spec files and `proofs/race.spec.luau` copied in. Each command ran under `./zn run --time …`, and the engine was restored and checked (`git diff --stat HEAD -- z-nile/engine` empty) after the one mutant. Since the prototype's base (`1758cf21..origin/main`), main has changed only `z-nile/tests/lib/fakecli.luau` among the engine and test libraries, in the fake CLI's dispatch modes, which these specs do not use. One `git fetch` of the three named branches touched the main checkout's remote-tracking refs at the start; nothing tracked changed.
- The eight files on the bare prototype: plan 5, memory 10, takeover 10, c0265's heartbeat 21, beat 11, edge 6, lost 15 and race 8, all passing.
- A probe spec (P1 to P6, quoted below) in the clone's `z-nile/tests/probe-r2/`.
- One mutant (F2).
- The 73 promoted specs that drive `status`, `release`, `stop`, `done`, `beat`, `fold`, `unfold`, `recombine`, `ready` or `start` (`grep -rlE '"(status|release|stop|done|beat|fold|unfold|recombine|ready|start)"' tests/acceptance tests/tooling`): RESULT.
Not findings:
- **The give-back refusal and `new raft`, `fold` and `recombine`.** None of them restamps an issue this checkout claimed itself: `new raft` takes `new` or `prepared` issues only (main.luau:1310), and `fold` and `recombine` take prepared issues and prepared or new rafts, without restamping members. So no per-issue memory goes stale through them; the one stale path is F5.
- **"An issue whose stamp a raft holds."** A single-issue raft correctly redirects its issue to itself. Retired rafts are not on publishable paths. A done raft never carries a live `preparing-` stamp. The one gap is a recombine's other raft (F3).
- **The rafting-to-work adoption.** It gives a worktree that lost a rafting claim no more than any fresh worktree's plain `--adopt` of the readied raft, and its plausible mutants are killed (dropping `current ^active-` is caught by memory.spec's c0090 case and by takeover.spec's `beat c0010 --adopt`).
- **Races.** A restamp between the verdict and the publish is refused (the race case), and the swap's leases and its retry hold. `done`'s check fails open, as stated. The one ordering hazard is F8.
- **Repository safety and bounded commands.** Every spec writes only its `.cache/c0274-*` fixture. E1 ran under `./zn run` with probe names, and `git ls-remote origin 'refs/heads/hb/*'` is empty today.
- **AC4's phrases.** None is present at bf5aa3c3, so each pin can fail.

### F1 [high] `--replace` lets the old lead of a taken-over readied raft back in: every lead is told the flag, and takeover.spec requires that re-entry after a real takeover
Where: c0274.md Design, the `./zn beat` bullet ("the act only the owner makes is the flag, which the skills tell the owner (z-stop, never z-run, never a refusal text)"); Assumptions to veto, first bullet ("The flag keeps the user's 'refuse' intact for an old lead that is never told it exists"). Prototype main.luau:1798-1806 (the `--replace` branch) and :53 (the usage line `beat <id> [--watch] [--adopt] [--replace S] [--stamp S]`); zz-rules SKILL.md:154 (the command row) and :194 (the Heartbeat paragraph); z-run step 0 ("continue from the raft branch and its pull request where they exist (z-stop step 4)"); z-stop SKILL.md:16. check.sh AC4 requires `--replace` in zz-rules. takeover.spec:408-455.
Evidence: P1 ran on the prototype tip.
1. Worktree `r2-oldlead` adopts R0010 (`active-heron-brisk-amber`).
2. `./zn lost` lists `R0010 active 178m`.
3. The main checkout runs `stop R0010` and then `ready R0010`, the takeover z-run step 0 prescribes. The claim is now `active-copper-indigo-indigo`.
4. The taker adopts R0010 in its own worktree, `r2-taker`.
5. The old lead's `done R0010` is refused: `R0010's claim was taken over (now active-copper-indigo-indigo): … stop here`.
6. In the old lead's worktree, `beat R0010 --adopt --replace active-heron-brisk-amber` exits 0, and its memory becomes `active-copper-indigo-indigo`.
7. A bare `beat R0010` exits 0 in both worktrees, and the old lead's next `done R0010` passes the stamp check (it stops later, at `no review-NNN.md`).

takeover.spec:418-450 runs the same sequence: `lost` lists R0010, then stop, ready, and wt4's `--replace <old>` succeeds and `done` no longer says the claim was taken over. So the sequestered spec requires that the worktree of a raft taken over as lost gets back in.

The old lead is told the flag in several places:
- zz-rules' Heartbeat paragraph, which every lead reads before moving or finishing tracked work, says "the owner who stopped and re-readied it names the stamp it remembers, `--adopt --replace <stamp>`, z-stop step 4".
- The command row and the usage line name `[--replace S]`, and AC4 makes `--replace` in zz-rules mandatory.
- z-stop's condition, "If you led the raft from that worktree", is true of the old lead.
- z-run step 0 sends every taker of a lost raft to z-stop step 4.

On any host other than the taker's, c0277's discard marker never exists, and c0277's hand-off names the memory as "the backstop, as for any old owner" behind that marker.
Critique: Round 1 F1 asked for "an act that only the owner makes and that the old process is never told to make". This flag is an act the old lead can make as easily as the owner, and the delivered docs tell it to every process. So the captured "its late moves are refused", and the user's "refuse", hold only while an old lead declines a documented flag. The Assumption asks the user to choose on a cost the design does not actually have. The tempting fix is to drop `--replace` from zz-rules and the usage line and keep it in z-stop. That still leaves z-stop's condition true of the old lead and z-run step 0 pointing at it, and it breaks the exhaustive-lists rule that put the flag in the command row. Separately, `stop`'s subject reads the same for an owner's stop and a taker's, so a readied raft's takeover is not recorded as a takeover (c0263's "recorded").
Consequences: The engine needs a fact, not a promise, to tell the owner's stop-and-ready from a taker's. It has one. A taker stops only a raft that `./zn lost` lists. The owner's keep path (z-stop step 4, "after a started raft") stops a raft whose draft PR is still open, which c0265 reads as parked and never lost, or a raft the owner is still beating. Recording that verdict changes `stop` (one verdict read, in the main checkout, which already fetches) and its subject. c0275's branch drop at `stop` must then come after that read, and a re-adoption reads one `git log` of origin/main.
Recommendation: Question the mechanism. Choose one of the following, and escalate to the user if the choice is not plain.
- (a) Record the verdict at `stop` and adopt without a flag.
  - `stop` judges the claim it gives back and records the verdict in its subject: `(claim <stamp>)` when the claim is live or parked, `(claim <stamp>, lost <n>m)` when it is lost, and `(claim <stamp>, unjudged)` when the verdict cannot be read.
  - A worktree that remembers `active-S` re-adopts main's new `active-…` claim with a plain `--adopt` only when the stop that ended S recorded it live or parked. A recorded loss, `unjudged`, or no stop record leaves it refused for good. This fails closed: an owner that let its own raft go lost continues the way a taker does, in c0277's numbered copy, which lands in the same PR.
  - Drop `--replace` from the usage line, zz-rules, z-stop and AC4, and drop row N4.
  - Cases:
    - The keep path: the raft is beaten at the stop, and a plain `--adopt` re-adopts it. `done` passes its stamp check.
    - The takeover: the raft is lost at the stop. The old lead's `--adopt` and `done` stay refused.
    - The stop subject pins `, lost`.
  - The layer rule says that c0275 drops the branch only after `stop` has read the verdict.
- (b) No in-place re-adoption: z-stop's keep path continues in c0277's numbered copy (`./zn worktree --takeover`), and the old worktree stays refused.
- (c) Keep `--replace`, and escalate to the user with the real cost. Every lead is told the flag (zz-rules, the usage line). An old lead on another host re-enters a taken-over raft with it. c0277's backstop is weaker. If the user keeps it:
  - Fix z-stop step 4's last clause, "it adds an empty commit, pushes, and reuses the open PR", which now follows the beat instead of `start`.
  - Put the re-adoption before `start`; under c0275, a `start` run first tells the owner "taken over … stop working it".
  - Then F2 applies.
Lesson: z-design/refusing-memory-names-how-its-owner-gets-back-in

### F2 [high] Nothing pins that `--replace` works only for a readied raft's `active-` claim: without that check every spec passes, and the old claimant of a taken-over prep re-adopts and its carried `prepared` lands
Where: prototype main.luau:1802-1803 (`string.match(remembered, "^active%-")` and `string.match(current :: string, "^active%-")`); Rules row N4, the only `--replace` mutant ("any `--replace` value accepted"); takeover.spec:316-361 (the old claimant runs `beat`, `--adopt` and `--watch`, never `--replace`).
Evidence: I deleted those two lines in the scratch clone and ran the three files: plan 5/0, memory 10/0, takeover 10/0. Under that mutant (P5):
- `p5-old` claims c0010, and `p5-taker` takes it over at AT.
- The old claimant's `status c0010 prepared` is refused.
- `beat c0010 --adopt --replace preparing-mellow-lynx-copper` then exits 0, and the old claimant's memory becomes the taker's stamp, `preparing-indigo-lynx-badger`.
- `status c0010 prepared` now exits 0.

On the real prototype, the same `--replace` exits 1 with `c0010's claim was taken over (now preparing-indigo-crimson-pink)`, and the carried move stays refused.
Critique: Those two clauses are all that keep the flag from reopening the user's "refuse" decision (the carried `prepared`) and AC3's refusals of the old claimant. An implementation that leaves them out passes check.sh.
Consequences: None beyond the cases, as long as `--replace` stays (F1 (c)). Under F1 (a) or (b) the flag goes, and this finding goes with it.
Recommendation: Add these cases:
- In takeover.spec's old-claimant case: `beat c0010 --adopt --replace <old>` is refused with `c0010's claim was taken over (now <stamp>)`, the memory is kept, and the carried move is still refused afterwards.
- The same for wt5's rafting claim, with `--replace <its old preparing stamp>`.
- In the readied-raft case: `--replace` is refused while main shows the raft stopped (no `active-` claim).

Add rows for the mutants "`--replace` for a preparing claim" and "`--replace` with no active claim on main". wt and wt5 then still run only refused commands, so the new cases hold on the envelope and on B.

### F3 [medium] Taking over one raft of a recombine splits their shared stamp: the other raft stays with the old owner, the branch they share is deleted, and the taker's carried move is refused
Where: Design, "The takeover" ("its members that hold the old stamp following"); zz-rules, Rafting ("recombine gives its two rafts one value, and that shared stamp is what lets the carried `status <keeper> prepared` take a member whose `raft:` on origin/main still names the other raft"); prototype main.luau:2032-2066 (only the target and its listed members are restamped) and :2079-2090 (the owner check that the shared stamp passes); this issue's new z-raft line ("continue from the branch the old rafting worktree pushed").
Evidence: P2.
1. Worktree `r2-recombine` runs `recombine R0020 R0030`. Both rafts carry `preparing-falcon-otter-otter`, and the worktree remembers that stamp for both. `./zn lost` lists R0020 and R0030 on separate lines.
2. `r2-raftaker`'s `status R0020 preparing` exits 0. R0020 becomes `preparing-copper-sunny-lynx`, R0030 keeps `preparing-falcon-otter-otter`, and `hb/preparing-falcon-otter-otter`, the branch both rafts shared, is deleted.
3. The old owner's `beat R0030` exits 0 and recreates that branch, and R0030 drops off `./zn lost`.
4. The taker continues from the old rafting branch by merging it into its worktree. The merge's one conflict is R0020's `status:` line, which the takeover restamped, next to the recombine's `grouped:` record, and R0020 now lists c0042. The taker's `status R0020 prepared` exits 1 with `c0042 belongs to R0030 on origin/main, not R0020`, read from origin before any local check.
5. Control: the same carried move by a recombine's own owner (`r2-control`, R0040 and R0050) passes that check and stops at `R0040 has no Theme`.

Critique: The captured "a lost rafting claim the same way, members following" and the decided "continue from the old agent's pushed branch" both fail for a recombine, which is an ordinary z-raft flow. The design's own reason for refusing a member taken alone ("would split the stamp and delete the raft's shared branch") applies to the other raft too. Round 1 F3's fix covered issues only, and z-raft's new line now tells the taker to do what is then refused.
Consequences: The claim is the stamp, not the raft id. `release` already gives back "every carrier of the raft's stamp" (`claimsLib.carriers`). If the takeover restamps every carrier, a takeover of either raft takes both. The subject names the id that was given, and the taker writes the c0116 claim file and the memory for each raft.
Recommendation: A rafting takeover restamps every backlog carrier of the old stamp on origin, which is the set `release` computes: the named raft, a recombine's other raft, and the members that carry it. Do it in one commit with the one swap, since there is one branch per stamp.

Add a takeover.spec case, in a worktree that runs nothing afterwards:
- Recombine two prepared rafts, let the claim go lost, and take over either id.
- Both rafts carry the new stamp, there is one `hb/` branch, and the subject records the old stamp.
- The taker's memory and claim files name both rafts.
- The taker's carried move passes the owner check (it may then stop at the Theme check).

Add a row for the mutant "only the named raft restamped". zz-rules and z-raft say that a recombined claim is taken over whole.

### F4 [medium] The old rafting owner's `release --force` ends the taker's live claim, and its plain `release` refusal points it at `--force` (repeat of design-review-001 F2, the late give-back)
Where: Design, "Telling the old owner" ("The old owner's late give-back is refused too: `status <id> new` (and `<R-id>`)"); prototype main.luau:1994-2000 (the refusal lives in `setStatus`) and :2746-2835 (`release`, unchanged except for `dropStamp`); takeover.spec:302-304 (accepts c0116's text); zz-rules' "Whose claim" bullet (SKILL.md:197, unchanged).
Evidence: `grep -nE 'stamp\((to|"new"|"prepared")\)' z-nile/engine/main.luau` on the prototype finds:
- 650: a word draw.
- 1173: `new issue`.
- 2012 and 2191: `setStatus`.
- 2813: `release`.
- 5485 and 5521: `stop`, which runs in the main checkout only.

So a worktree gives back a claim through `setStatus` or `release`, and only `setStatus` checks the memory.

P6:
1. `p6-old` makes a rafting claim with `new raft`.
2. `p6-taker` takes it over at AT, as `preparing-walrus-copper-plucky`.
3. The old owner's `release R0010` exits 1 with `R0010's claim preparing-walrus-copper-plucky is not this checkout's: give back only your own claim (--force when the user says it is abandoned)`.
4. The old owner's `release R0010 --force` exits 0 (`released c0050 (new), R0010 (new)`). That ends the taker's live claim while the taker still remembers it.

Critique: zz-rules calls `release` "the published give-back" of a rafting claim, so the captured "its late moves are refused" misses the main give-back. The refusal text also tells an old owner, whose memory proves it lost the claim, that the claim may be abandoned and how to force it. This is the second hole in round 1's give-back mechanism, which put the check into one command instead of every give-back.
Consequences: `--force` stays the user's way to release an abandoned claim from any checkout that has no proof of loss. A refusal shared by every give-back means a future give-back command cannot miss it.
Recommendation: Put one check before the publish, called by `setStatus`'s give-back and by `release` (with or without `--force`): a checkout whose memory reads `taken` for the claim is refused with the takeover text, which says that `--force` belongs to a checkout that never held the claim. zz-rules' "Whose claim" bullet then says that give-backs are open to anyone except a checkout whose memory shows it lost the claim. Add a takeover.spec case beside the `status <R> new` one: wt5's `release <R> --force` is refused and the stamps are unchanged. Add a row for the mutant "release not checked".

### F5 [medium] `status <R-id> new` does not end a raft's memory: the c0116 claim file stays and `stampMemory` reads it, so the checkout that gave the raft back is later told its claim was taken over
Where: Design, "The claim memory" ("`status <id> new` drops it"); the Rules row "a claim-ending command ends the memory (give-back, release)", which memory.spec checks for an issue only; prototype main.luau:416-421 (`stampMemory` falls back to `tracker-claim-<id>`), :2205-2225 (`dropStamp`; the claim file is removed only for an issue, or for a raft moved from `active`) and :4900 (`done` drops only the stamp file).
Evidence: P3.
1. `r2-giver` runs `new raft chore gb c0050`. Both memory files hold `preparing-badger-mongoose-lucky`.
2. After `status R0060 new`, the files read `tracker-stamp-R0060=absent tracker-claim-R0060=preparing-badger-mongoose-lucky`.
3. `r2-next` claims R0060.
4. The giver's `beat R0060 --adopt` exits 1 with `R0060's claim was taken over (now preparing-lynx-lynx-mongoose)`, and its `status R0060 new` would be refused the same way.

A legacy-started raft's worktree keeps `tracker-claim-<R>` after `done` the same way (`start` writes it at main.luau:4092).
Critique: c0275 and c0277 read where the memory ends. c0277's `--takeover` picks "the non-discarded worktree whose claim memory names the id", through the same fallback. The raft half of the rule is false, and no spec pins it.
Consequences: A give-back that ends the claim also ends c0116's "this checkout owns the rafting claim", and `release` already removes that file. So removing both files changes no c0116 meaning.
Recommendation: Every place that ends the memory removes everything `stampMemory` reads: `status <R-id> new` and `done` also remove `tracker-claim-<id>` (or `dropStamp` removes both files). Add a memory.spec case:
- `new raft`, then `status <R> new`: both files are gone.
- Another worktree then claims the raft.
- The giver's bare `beat` is refused with "does not hold", not "taken over".

Add a row for the mutant "a raft's give-back drops only the stamp file".

### F6 [low] When a raft takeover is refused because a member holds a claim under its own stamp, the refusal says "take it over (or give it back) first", but taking the member over leaves the raft refused
Where: prototype main.luau:2065; the `reasoned` Rules row "a member holding a claim of its own under another stamp is named in the raft's refusal".
Evidence: P4.
1. Run `new raft chore mm c0061 c0062`, then `status c0062 new` and `status c0062 preparing`. c0062 now carries `preparing-otter-mongoose-quiet`, and the raft `preparing-plucky-sunny-lucky`.
2. At AT, the taker's `status R0070 preparing` exits 1 with `c0062 is preparing on origin/main under a claim of its own (preparing-otter-mongoose-quiet): take it over (or give it back) first, then R0070`.
3. The taker takes c0062 over (exit 0).
4. `status R0070 preparing` exits 1 again, now naming `preparing-crimson-silver-copper`.

Recommendation: Either carry such a member along when its own verdict is lost (its branch in the same atomic push; F3's carrier set does not cover it, because it carries another stamp), or have the refusal say what works: "take it over, give it back (`./zn status c0062 new`), then `./zn status R0070 preparing`". P4 is the cheap fixture the row's reason asked for.

### F7 [low] "The taker's branch is untouched" is asserted before the give-backs, not after them
Where: takeover.spec:340 (`tipOf(taken)`, checked after the beats) and :350-359 (the give-backs, which check only the stamps); AC3 ("… and the taker's branch is untouched").
Evidence: The layer rule allows c0275 to "drop a claim's branch at `status <id> new`". A drop that reads origin's stamp before c0274's refusal would delete `hb/<the taker's stamp>`, and the case would stay green.
Recommendation: Move the `tipOf(taken)` assertion after the two give-backs, and add an assertion on the rafting claim's branch tip after wt5's refused give-back.

### F8 [low] The swap's create-only write turns takeover.spec red if c0275 puts its first beat where its hand-off says, and no envelope run tried that placement (repeat of design-review-001 F11, the swap's lease)
Where: heartbeat.luau:288 (`lease = ""`, pinned by plan.spec's first case); main.luau:2208-2211 (the swap after the publish); envelope.patch and its variants (the first beat runs after the whole handler); c0275's hand-off ("First beats: `status <id> preparing` … beat right after their publish").
Evidence: The refute says "c0275's first beat finds the branch the swap made, and a create-only write keeps a second creator out". But the only other writer of `hb/<the taker's fresh stamp>` is the taker's own first beat. If c0275 puts that beat right after the publish, before `swapBranches`, both swap attempts are rejected and `hb/<old>` stays. takeover.spec's `tipOf(before) == ""` then turns red on the final tree. The envelope and both variants put the beat after the handler, so that placement was never run.
Recommendation: Either write the taker's branch with the lease of what is there (plan.spec's case then pins the sha seen), or state the order in the layer rule ("c0275's first beat after a takeover runs after `swapBranches`") and run the envelope with the beat right after the publish to show the red that rule guards against.
Lesson: z-design/bottom-layer-pins-only-what-upper-layers-keep

### F9 [low] The new lesson `refusing-memory-names-how-its-owner-gets-back-in` teaches the mechanism that F1 shows unsound
Where: z-nile/skills/z-design/lessons/refusing-memory-names-how-its-owner-gets-back-in.md, How to apply ("give the owner an explicit act (a flag naming the exact stamp it remembers) that the old process is never told, tell it only in the skill that documents the flow").
Evidence: This issue's own design has to name the flag in zz-rules, in its command row and in the usage line (the exhaustive lists), so "never told" cannot hold for any flag.
Recommendation: Rewrite How to apply. First look for a fact the engine can read that tells the owner's act from a taker's (here, the verdict at the moment the stamp changed). An act that is "never told" to the old process is no guarantee once the rules skill and the usage line must list it.

Verdict: changes

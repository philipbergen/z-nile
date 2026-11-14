# Review 002: R0100 (design mode, raft mode)
Inputs: raft-heartbeat at 2cc860aba (`z-nile/.tracker/rafts/R0100/R0100.md`, `check.sh`, `design-review-001.md`, `design-refute-001.md`, `harvest.md`); the five members' documents and `check.sh` files at that commit (the branch changes only their `raft:` lines); `origin/proto-heartbeat-stack` 13e667a6 (`main.luau`, `heartbeat.luau`, `dispatcher.luau`, the z-run, z-work, z-stop and zz-execute skills); `origin/proto-c0277` 2a6e776a; `origin/main` 672423a0 (no engine, lib or skill change since the stack's base a65b4f41); R0099 and c0282 on the local branch `raft-provenance` b1241016e (refolded 00:23 today) and on `origin/main`; c0284 on `raft-provenance`; R0099's prototype `proto-provenance-stack` 2fa3841e; c0317 on `origin/main`.
Grouped: [c0265@15845fae8f23, c0274@9d21047b9952, c0275@f3fc806784b0, c0276@dfa2ec9f736d, c0277@cc9e6ff61417]

Checks I ran, and what holds:
- **Front matter.** `grouped:` in R0100.md matches the record quoted above.
- **Stack provenance.** `origin/proto-heartbeat-stack` is 13e667a6, the merge of 2a6e776a and a65b4f41. a40faeb3, 965c0fd6 (c0276), ade6108b and 9207cea7 are all ancestors of 2a6e776a.
- **RC1.** `./zn workstreams R0100` prints c0265 to c0277 as waves 1 to 5 and `parallel: no`, so RC1 passes.
- **RC2, on the stack's files.** It finds:
  - `function heartbeat.takeoverPlan`, `function heartbeat.markParse`, `function heartbeat.discardParse`, `function hb.judgedFor` and `function hb.boardVerdicts` once each;
  - one `^local hb\b` (BSD grep, which `bash -c` gets, counts `local hb = {}` and `local hb: {…} = {}` and skips `local hbx`);
  - `local boardview`, `sessionread` and `sessions` kept.
- **RC3 and RC5, on the stack's files.** The z-run shim carries all eight RC3 phrases and z-work carries all four RC5 phrases. On `origin/main` all eight and three of the four are missing (see F5 for the fourth).
- **Paths.** `ac.sh` exports `ZN_ROOT`, and every RC line uses it.
- **Whole-raft signatures.** These match the stack: `plan(…, remembered?)`, `watch(…, gone?)`, `gone(…, discarded?)`, `holds`, `staleMember(facts)`, `claimBeat(ctx, id, cwd, started, onDiscard?)`, and `hb.takeover` split into `hb.takeover` and `hb.discard`. The plain lookup (`cmd.worktree`) calls `heartbeat.staleMember` and then `hb.discard`. `hb.discard` writes only to stderr, so `cd "$(./zn worktree <R>)"` gets one line.
- **Promotion.** `withPromotedCopies` copies only `<item>/acceptance` (main.luau:4583), so a real `done` never promotes `proofs/`. The stack's failing case is its promoted `tests/acceptance/c0275/proofs/beater.spec.luau`. The Experiments phase reports this honestly.
- **The 200-local cap.** Top-level `local` lines: main 199, stack 193. That fits the measured 4 and 10 spare.
- **Layer rule 7.** c0274:70/123, c0275:102 and c0277:112/148 quote "Drop in-place re-adoption" word for word.
- **E11.** R0100 quotes c0284's E11 as it is.
- **c0317.** It is `new` with `depends_on: [c0263, c0274]`, as R0100 says.

### F1 [high] The Order section names c0277 twice, so the engine refuses to start, finish, stack, trace or land the raft
Where: R0100.md, `## Order & dependencies`, line 97 ("5. c0277 (layer 5 …") and line 102 ("**Layer 5 was re-prepped once** (… the user's ruling "Re-prep c0277, keep R0100 whole (Recommended)")"); engine: `stack.luau:146` (`string.gmatch(section, "[fdc]%d%d%d%d")`), `stack.luau:207-208`, `layergit.luau:42`.
Evidence: `layergit.orderedMembers` passes the whole section to `stack.order`. That function reads every `[fdc]NNNN` in it with no word boundary and refuses a repeat. Line 102, added in 2cc860aba (f4077254's Order named each member once), quotes the ruling with the id in it. I copied `stack.luau` and R0100.md to a scratch folder and ran `stack.order` on the section exactly as `raftSection` cuts it, with the five members and their `depends_on`. The probe was `./zn run --time 30 -- lune run <scratch>/order.luau`, and it printed `refused: c0277 is listed twice in R0100's Order`.

`orderedMembers` is called by:
- `layergit.startLayer` (`./zn start`, layergit.luau:235);
- `cmd.finish` (main.luau:3745);
- `cmd.stack` (:3993);
- `traceProblems` (:4861);
- `cmd.done` (:5026).

`./zn status <R> prepared` and `ready` do not call it, so the raft would be approved and readied, and then refused at its first `./zn start`. RC1 can't see this: `workstreams` doesn't read the section, so RC1 passes while its label ("the five layers run in the Order") is false of the order `start` uses.
Critique: The tempting fix is to delete the id from line 102. But the sentence quotes the user's ruling verbatim, and rewording a verbatim quote is the wrong fix.
Consequences: Moving the paragraph keeps the quote. Every later edit inside the section (a fold note, another ruling) can bring the defect back, and RC1 will keep passing.
Recommendation: Move the "Layer 5 was re-prepped once" paragraph, with the verbatim ruling, out of `## Order & dependencies`, into the Experiments phase or a short `## Re-prep` section above it. Then run the lesson's check on the section and record the output in the raft document: `./zn stack R0100`, or the `stack.order` probe above. It must print c0265, c0274, c0275, c0276, c0277 and no refusal. Optionally make RC1 also run `"$ZN_ROOT/zn" stack R0100` and require success, so the label is true of the order `start` reads.
Lesson: z-raft/order-names-members-once

### F2 [medium] Nothing ran the slow tier on the stack, though it holds the specs for every command the five layers change and the re-prep changed `./zn worktree`
Where: R0100.md, Experiments phase, "Results on the stack" (only `--affected` and each `./zn check`), and Risks, "The slow fixtures" (line 157: "the affected gate runs the whole z-nile suite"); c0277.md:211 (E3) and :214 (E7); c0277.md:296 (Implementation step 1); `z-nile/skills/zz-test/SKILL.md:12-13, 60`.
Evidence: `--affected` and `--full` both skip `z-nile/tests/slow.tsv` (zz-test: `--full` is "every spec outside the measured slow tier"; `--slow` is "not part of the affected or full gates"). Only the post-merge net runs it, after the stack has landed. RC0 is `--affected`, so `./zn done` never runs it either. The sentence "the affected gate runs the whole z-nile suite" is false.

The slow tier holds the specs that drive what the layers change:
- `c0068/stop` (7 `stop` and 3 `worktree` calls);
- `c0067/ready` (4 `worktree`);
- `c0116/claims` (20 `worktree`, 21 `preparing`);
- `c0117/control-cli` (75 dispatch, 2 stop);
- `c0117/dispatch-cli`;
- `tooling/dispatch-guards` (39 dispatch);
- `c0005/worktree`, `tooling/worktree-fetch`, `c0053/commands-sync`, `c0114/roots-cli`, `c0046/launch`.

The re-prep makes a plain `./zn worktree <name>`, and so the dispatcher's `worktree(ctx, …)` (dispatcher.luau:241), discard any family member whose remembered claim `origin/main` no longer shows. c0277's E3 ran six slow specs on the pre-re-prep tip (2026-11-12). E7, the re-prep's evidence, ran `--affected` and the proofs only. Its six-spec list leaves out the stop, ready, claims and dispatch specs above. No slow-tier run is recorded for layers 1 to 4: c0265, c0274 and c0275 change `setStatus`, `stop`, `done` and the claim publish, and none of their documents mentions the slow tier.
Critique: The tempting fix is to put those specs in a `check.sh` line. That is paid at every `finish`, `restack` and `done` (zz-test/check-sh-never-runs-the-slow-tier).
Consequences: Any red result is an Override that some member's design must name, with its chore, so that member goes back through z-design (z-raft unfolds it). The one-time cost is about 45 minutes of spec time serially, by `slow.tsv`'s figures (827 + 451 + 419 + 406 + 153 + 149 + 148 + 127 s), and less across the runner's lanes.
Recommendation: Run `z-nile/check.sh --slow -- <the specs above>` once on `proto-heartbeat-stack` (13e667a6) under `./zn run`, and record each result in the Experiments phase. In Risks, replace "the affected gate runs the whole z-nile suite" with the slow-tier fact. For each layer, name the slow specs its executor runs once before that layer's `finish`, as an implementation step and not in `check.sh`:
- c0265, c0274, c0275: stop, ready, claims, control-cli, dispatch-cli, dispatch-guards;
- c0277: all of the above plus c0277's six.
Lesson: z-design/guards-name-slow-tier-specs

### F3 [medium] The z-run shim and z-work step 7 give the worker a lost-first order that z-work, `work.luau` and the raft itself say it doesn't have, and Risks still says this was "Flagged for the user"
Where: stack `z-run/SKILL.md:13` ("Take work that `./zn lost` lists before work not yet started"); stack `z-work/SKILL.md:16` (step 7: "An unnamed session … runs `./zn work next` with no raft; take work that `./zn lost` lists before work not yet started"); `z-work/SKILL.md:8` ("The ordering is `./zn work next`; this skill has none"); `work.luau:16` ("c0249: … lost work is not taken first") and `:18` ("An unnamed session does not resume one, and does not take it over"); R0100.md:137 ("the worker loop takes lost work only after the rank and the loop land"), :139 ("(taking `./zn lost` work first)") and :154 ("Flagged for the user in Open to the human"); `## Open to the human` ("None"); c0277.md:151; c0265 check.sh AC5 ("the lost-first pick in … z-run").
Evidence: The raft states both rules. Line 137 says the worker doesn't take lost work first until c0249 and c0253. Line 139, c0277's design and the stack's text tell sessions to take `./zn lost` work first. The shim is read by a named session (z-run is "z-work with that raft named", which "carries that one and then stops"), so it tells a session carrying R0010 to take another, lost raft first, by stop, ready and `--takeover`. Step 7 adds an order to the one skill that says it has none, and only for sessions that were discarded. An ordinary unnamed session (step 1) still takes `work next`'s not-started raft first.

The root is c0265's AC5, which places "the lost-first pick" in z-run. Since #318 made z-run a shim, z-run has no pick to hold it. Round 1's F3 raised this as a user decision. The refute answered "fixed" by declaring it not open, but Risks line 154 still says "Flagged for the user in Open to the human". That is the sentence F3 quoted, and Open to the human says None.
Critique: The tempting fix is to delete one of the two sentences. Either choice decides, without the user, where c0265's captured outcome lives now: "anything that is in progress but lost … is higher than anything that is not yet started". In the z-work world the pick is `work next`.
Consequences: Whichever rule is chosen has to read the same in five places: the shim, z-work step 7, R0100.md:137/139, c0277.md:151 and Risks:154. The pins still pass with any wording that keeps the phrases: `./zn lost` in z-run (c0265 AC5, RC3) and in z-work (c0277 AC6, RC5). So no spec or `check.sh` changes. c0277's design sentence (line 151) changes either way. That is a text change to a member, and its checks are unaffected.
Recommendation: Escalate to the user. Put one bullet under `## Open to the human` in the dispatcher's form: "c0265's lost-first pick has no pick to live in since z-work". Options:
- (a) Lost-first waits for c0249 and c0253, as line 137 says. The shim says only where lost work is listed and how a person takes a lost raft over. Step 7's unnamed branch runs `./zn work next` with no raft and no order of its own. This defers c0265's z-run outcome for the main worker until those land.
- (b) Prose lost-first in z-work now: an unnamed session runs `./zn lost` before `./zn work next` and takes a lost raft over. This contradicts z-work line 8 and `work.luau`'s c0249 note until c0249 lands, so z-work's own design changes too.
- (c) An engine change in `work next`, in c0253, c0249 or a new member.

In every option, a named session's shim never tells it to take other work. Delete or fix the Risks sentence to match the ruling.
Lesson: z-design/restated-rules-move-together (a refute answered "fixed" did not find the sentence the finding quoted still there); z-raft/escalations-are-bullets

### F4 [medium] The Interfaces to the provenance raft disagree with R0099's documents: c0282 still says the takeover's provenance record is this raft's call
Where: R0100.md, "Interfaces to the provenance raft" (lines 84 to 89); c0282.md:73 on `origin/main` and on `raft-provenance` b1241016e; R0099.md:53 and :70-76 on `raft-provenance`; `proto-provenance-stack` 2fa3841e, `main.luau:22, 29, 381` and its `dispatcher.luau` hunks.
Evidence: There are four disagreements.

(1) c0282, refolded into R0099 at 00:23 today, still ends its row for c0265, c0274, c0275 and c0277 with "A takeover's own record (c0265) is a `./zn provenance record` call of theirs." R0100 says it writes no record and that c0317 owns it. R0099.md doesn't name c0317. Round 1's F4 asked for c0282's sentence to be changed, and it wasn't.

(2) R0100 says "R0099's layers add requires (`provenance`, `mergerecords`, `who`, `boardprov`)". R0099's prototype adds top-level `local mergerecords = require(...)` (line 22), `local provenance = require(...)` (line 29) and `local lifecycle = {}` (line 381). `who` and `boardprov` are required lazily (R0099.md:53: "c0280 and c0284 require inside `cmd.who`").

(3) R0100 lists the shared files as `main.luau`, `status`, the board, zz-rules, z-design and the README. Both rafts also change `dispatcher.luau`: each adds a top-level require (`heartbeat` and `provenance`) and a hunk in `modelStep`, R0099's `env.ZN_ACTOR` at 953 and R0100's `claimBeat` block at 1046. Both also change `cmd.done`. R0099 names both overlaps ("Distinct hunks except `setStatus` and `cmd.done`").

(4) R0099 says the heartbeat raft "records `main.luau` at 206 top-level `local` lines". That is c0276:115's note from before c0265's fix. R0100 measured 10 spare.
Critique: If R0099 lands second, its executor reads "a call of theirs" and either expects a call R0100 never makes, or writes one with no design. That is round 1's F4 hazard, still open on the other side.
Consequences: R0100 can't edit c0282. The fix is a message to R0099's lead plus R0100's own corrections, and the second lander's count stays the real check.
Recommendation: In R0100, list `dispatcher.luau` (the require block and `modelStep`) and `cmd.done`. Order the latter as R0099 does: refusals first, `delivered` rows in the merge, this raft's sweep after the push. Replace the requires list with `mergerecords`, `provenance` and `lifecycle`, and note R0099's stale "206" against the measured 10. Send R0099's lead the request to replace c0282's last sentence with c0317 and to name c0317 in R0099's Interfaces. Record that request in R0100, so the second lander knows which side was asked.
Lesson: z-raft/cross-raft-order-written-in-both; z-design/quote-other-preps-before-promising

### F5 [medium] RC5 can't fail on `with no raft`: main's z-work already says it, so the rule's unnamed-session branch is pinned by nothing
Where: R0100 check.sh:43-47 (RC5); `origin/main` `z-nile/skills/z-work/SKILL.md:15` (step 6: "then run `./zn work next` with no raft"); c0277 check.sh AC6 (z-work phrases).
Evidence: `grep -cF "with no raft"` on main's z-work gives 1. RC5's other three phrases (`you were discarded`, `./zn lost`, `--adopt`) are absent on main. c0277's AC6 adds `never run \`./zn worktree <R>\``, which pins the "neither" half. Round 1's F2 asked for a pin on "the no-raft fallback", but nothing pins "drops the raft id". A z-work text that says "you were discarded: stop" for both modes, with `./zn lost` and `--adopt` only in step 10, passes RC5 and AC6.
Critique: The tempting fix is a longer phrase that main also happens to contain.
Consequences: The new phrase must be absent on `origin/main` and present on the stack's z-work. `drops the raft id` is 0 on main's z-work and 1 on the stack's z-work and shim. `never pass its id again` is 0 and 1.
Recommendation: Replace `with no raft` in RC5 with `drops the raft id`, and optionally add `never pass its id again`. Record in the raft document that each RC phrase was checked absent on `origin/main`. It isn't high because the half that prevents harm (never looking the worktree up again) is pinned by c0277's AC6.
Lesson: zz-test/no-vacuous-pass

### F6 [low] The Whole-raft tables and Layer rules miss the shared surfaces the re-prep made, and a few counts and lists disagree
Where: R0100.md:52-61 (the `main.luau` table), :27 and :67 (shared surface and skills), :74-81 (Layer rules), :100, :139, :142; c0274.md:53; c0275.md:107.
Evidence:
(a) c0274's `cm` table is shared, and the table has no row for it. c0275 adds `dir` to `cm.read` (proto-c0275 main.luau:440). c0277 adds `cm.ids`, makes `cm.remember` drop `.cache/fresh`, and reads `cm.read(x, member.path)` in the lookup, which relies on layer 3's `dir`.
(b) c0277's sweeps in `sync` and `worktree-prune` and its `reap` listing (stack main.luau:9624) are not in the table.
(c) The Layer rules don't say the plain lookup is now a second discard path: outside `--takeover`, with no lost verdict, for a claim already over. c0274's layer rule lets c0277 discard through `--takeover` "(which needs the lost verdict …)". Rule 4's "none of c0275's cases marks a worktree discarded" should now read "none of c0274's or c0275's cases looks up a worktree that remembers an over claim". That is true on the stack (4/4 and 4/4), but it isn't written down.
(d) The z-work steps the rule goes into are stated four ways: "steps 1 and 7" (line 139), "1, 7, 10" (c0277), "1, 6, 7, 10" (the refute), and the stack edits 1, 7 and 10.
(e) Exit criteria says "RC1 to RC4" and lists RC5 before RC4.
(f) The Theme says "about 3,300" changed lines and the Order says "about 3,200".
(g) Line 100 calls layer 5 one of "the lightest dependents". At 1,200 lines it is the heaviest.
(h) Line 27 and the skills paragraph leave out `z-nile/skills/z-work`, which c0277 touches and RC5 reads.
Critique: Each is small. Together they mean the table is no longer "copied from the members' designs".
Consequences: None beyond the text.
Recommendation: Add a `cm` row (c0274 creates it; c0275 `cm.read(id, dir?)`; c0277 `cm.ids` and the `cm.remember` change) and a `sync`/`worktree-prune`/`reap` row. Add Layer rule 8: the plain lookup discards through `hb.discard` a member whose claims are all over; c0274's and c0275's cases never look such a worktree up; the evidence is `./zn check c0274` and `./zn check c0275` on the stack. Make the step list "1, 7 and 10" everywhere. Fix the RC count, the size, "lightest" and the surface lists.

### F7 [low] c0277's own text still describes the lookup as it was before the re-prep, and no document says that existing worktrees are discarded on their first lookup after landing
Where: c0277.md:164 (Chore checklist (1): "`./zn worktree <name>` looks up the family and no longer reuses a discarded one's path (same answer for every worktree that was never discarded …)"); c0277.md:166 (Existing work (a) to (f)); c0277.md:124-139 (the pure list, which lacks `staleMember` and `isMember`); stack main.luau:442 (`cm.ids` reads `tracker-claim-<id>`); origin/main main.luau:1372, 1686, 1871, 1978, 2103, 3662 (writers of `tracker-claim-<id>`).
Evidence: After the re-prep, a never-discarded worktree whose remembered claim ended gets a different answer: it is renamed and a `-1` copy is returned. `cm.ids` counts c0116's `tracker-claim-<id>`. Main's engine writes that file at `new raft`, `fold`, `recombine`, `start` and `status <id> preparing`. It removes the file at an issue's `prepared`, but never at a raft's rafting end. So once R0100 lands, the first plain lookup of an existing rafting worktree, or of a prep worktree whose claim ended, discards it. That is the user's rule, but neither c0277's migration list nor the raft's Risks says so. `heartbeat.staleMember` is in the raft's table but not in c0277's own pure list.
Critique: It's a doc gap, not a defect. But Existing work is where an owner of an active worktree learns what changes for them (item (e): "listed in the PR for their owners").
Consequences: None in code.
Recommendation: In c0277 (text only; its checks are unaffected), correct checklist (1), add item (g) to Existing work naming the `tracker-claim-<id>` case, and add `staleMember(facts: {ClaimFact}): boolean` and `isMember` to the pure list. Add one line to R0100's Risks that points to it.

### F8 [low] The interim text in Risks only matters if layer 5 is unfolded, and it points at z-stop's "start fresh", which closes the PR and deletes the branch
Where: R0100.md:153 ("Stopped and readied again, before the worktree layer lands"), :100 (the unfold advice), :159 (Rollback); c0277.md:166 (f); `origin/main` `z-stop/SKILL.md:16`; `zz-execute/SKILL.md:85, 90` ("`./zn done` already landed the stack (one `--no-ff` merge)").
Evidence: The stack lands in one merge, so no `main` ever has layers 2 to 4 without layer 5. The text reaches main only if layer 5 is unfolded, which line 100 suggests "if the raft lags". The bullet's parenthetical "(`git worktree remove`, z-stop step 4's start-fresh path)" names two different things. z-stop's start-fresh path is "close the PR and delete the branch (`gh pr close <pr> --delete-branch`, then `git -C <root> branch -D <branch>` and remove its worktree)". c0277 (f) says "remove the old worktree and its branch". On z-work's routine block path (step 5: stop, answer, ready again), that throws away every finished layer. Rollback (line 159) says nothing about discarded worktrees and numbered copies left behind when layer 5 is reverted. Their markers stay. A prep's branch checked out in `prep-x-1` makes the reverted `./zn worktree prep-x` refuse with `already used by worktree`.
Critique: The executor of layer 2 would copy one of the two meanings.
Consequences: Writing the text only with an unfold of layer 5 removes churn from layers 2 and 5.
Recommendation: Say the interim text ships only with an unfold of layer 5, and that it is:
1. `git worktree remove <old path>` (the memory goes with it), keeping the branch and the PR;
2. `cd "$(./zn worktree <R>)"`;
3. `./zn beat <R> --adopt`;
4. z-stop's keep path (`start` on the branch).

Add to line 100 that unfolding layer 5 reopens round 1's F1 and must carry this text. Add a Rollback line: after a revert of layer 5, use the numbered copies by path and remove the `-discarded-<n>` worktrees by hand, once `./zn reap`'s list has been read.

## Lesson candidates
- z-raft (a note on order-names-members-once): `./zn workstreams` doesn't read `## Order & dependencies`, so an RC that pins workstreams proves nothing about the order `start` reads. After any edit inside that section (a re-prep note, a quoted ruling that names a member), run `./zn stack <R>` and record it. Why: R0100's round-2 edit put a verbatim ruling with a member id into the Order while RC1 stayed green. Check: was `./zn stack <R>` (or `stack.order` on the cut section) run after the last edit to the Order section, and did it name each member once with no refusal?
- z-raft (a note on guards-name-slow-tier-specs): a raft's composition proof names, for each command its members change (stop, ready, status, worktree, dispatch), the `slow.tsv` specs that drive it, and runs them once on the stack with `z-nile/check.sh --slow -- <paths>`. A re-prep that changes such a command reruns them. Why: R0100's five layers change stop, ready, claims and the worktree lookup, and only the post-merge net would have run their slow specs. Check: which slow-tier specs drive the commands this raft changes, and where is their run on the current stack recorded?
- zz-test: a phrase an RC or AC pins to prove new text exists must be absent from `origin/main`'s file. Why: RC5's `with no raft` was already in main's z-work step 6. Check: does `git show origin/main:<file> | grep -cF -e <phrase>` print 0 for every phrase the check pins?

Verdict: changes

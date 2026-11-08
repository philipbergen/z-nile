# Review 006: c0265 (design mode)
Inputs: prep head 777eb6e31ecd1c5a377c435b565b716738f718f1 (`tracker: prep c0265 user answers (takeover ok, storage method re-examined)`), origin/main e7afa5c7; c0265.md, check.sh, acceptance/{heartbeat,beat,lost,edge}.spec.luau, proofs/{dispatch,race}.spec.luau, experiments/heartbeat.proto.luau, design-review-001..005.md, design-refute-001..005.md, harvest.md; `./zn capture c0265` (prints `(no capture commit: first add)`: c0265's first commit is the rename, 081392e0, #258, so this is not a confirmed capture by the marker rule. I judged scope from history: f0265's capture 5208b315, plus the user's rewrite in #258, which added "so every host and the board see it" and "the takeover is recorded (c0263)"); `./zn lessons --when design --full`, `./zn lessons --skill zz-review --full`; z-nile/engine/main.luau (guarded, publishing, READ_ONLY, originPaths, refuseStale, setStatus, cmd.status, cmd.sync, mergeOrigin, cmd.worktree), publish.luau:590-606, claims.luau, board.luau, dispatch.luau (gate kinds), z-nile/lib/fence.sh (pickman_guarded), z-nile/tests/lib/{fence,trackerfix,fakecli}.luau, z-nile/README.md (Order, Roadmap, The board), z-nile/templates/raft/doc.md, c0263.md.
Replays (from z-nile; prototype copied to `engine/heartbeat.luau` and deleted after; `git status` is clean): `../zn run --time 300 -- lune run tests/run -- …`: heartbeat 17/17. lost 2/11 (setup, and the taker's carried move). edge 1/3 (setup). beat 1/10 (setup). Every other case fails on an assertion or on a missing command (`usage:`), not in setup. `./zn promote-check c0265` prints OK. check.sh: `bash -n` passes, and `AC_LIST=1` lists 6 criteria.

Round-5 answers, checked in the documents and not in the refute:
- F1 is fixed: beat.spec:193-206 uses the fence's spelling, appends to the inherited list, and asserts the entry is byte-identical. The Rules row still lists the mutant the old spelling killed (F6 below).
- F2 is fixed in the Design (every claim path records the stamp, `unfold` is in First beats) and has a lost.spec case. But E8 was not re-run on the new claim paths (F5), and the new case breaks the case after it (F1) and depends on an order the Design does not fix (F4).
- F3 is half fixed: the race and `fold` cases are back in `edge.spec`. The throttle case and the gating were not done (F7).
- F4, F5 and F7 are fixed.
- F6 is fixed except for three leftovers (F9).

Walk summary: I traced every case. For each I recorded which checkout runs the command, its clock (ZN_NOW, or the real clock where `since` comes from commit times), each worktree's `.cache/tracker-beats` entries and epochs, the beats on origin, what each `plan` deletes, and what each shim arm does.
- beat.spec: every case passes for a correct implementation, and its listed mutants fail, except "comparing path strings" (F6). In case 6 the beat fetches first, so the fetch alone keeps the other terminal's beat. The listed mutant "no fetch and no grace" is the honest one.
- lost.spec: the cases at lines 127-286 pass for a correct implementation. The case at line 288 does not (F1).
- edge.spec: both cases pass. In the race, publish's push is `<sha>:refs/heads/main` (publish.luau:602), so the shim's `*:refs/heads/main*` arm fires. `$REAL_GIT` restamps origin, the lease rejects the push, and the retry's callback sees `preparing-sunny-heron-lynx`.
- proofs/dispatch.spec: passes for a correct implementation. A dispatcher that beats only before or after the step fails it.
- proofs/race.spec: every case passes, but its setup runs twice (F8).

On the storage method (the user's "we need to come up with a good method"), I think the comparison is fair and the ref is the right choice against the capture's intent: no churn on `main`, it works before a PR exists, one `ls-remote` reads it, and E2 proved it on the real origin. It misses one column, the board, which the c0265 capture names and which the method paragraph claims is served (F2). That gap does not change the choice: a file on `main` would put the beat in front of the board for free, but at the churn the capture itself warns about.

### F1 [high] lost.spec's old-claimant case cannot pass: the rafting case added in round 5 runs `sync` in `wt` first, which prints c0010's one-time "taken over" notice and drops its entry, so line 294 finds nothing (repeat of review-004 F1's mechanism)
Where: lost.spec:267 (`must(zn(wt, { "sync" }, at), "sync")`, inside "a lost rafting claim is taken over the same way"); lost.spec:292-295 (the next-but-one case: `local sync = zn(wt, { "sync" }, at) … t.expect(has(sync.stderr, "taken over")).toBe(true)`); Design, Automatic beats ("if origin's stamp for the id differs from the entry's … the entry is deleted … it says once on stderr `<id>'s claim was taken over (now <stamp>): stop working it`").
Evidence: the cases run in this order:
- 240: wt2 takes c0010 over, so origin's stamp moves from S1 to S1′.
- 254: wt2 takes R0020 over, S3 to S3′. Then `wt` runs `sync` at `at`. `sync` is not `READ_ONLY` (main.luau:5989-5999). wt's entries still hold c0010 = S1, c0020 = S2 and R0020 = S3, all from T0, since wt has run nothing since setup. The autobeat drops c0010 and R0020, prints both notices, and beats c0020.
- 278: runs in wt2 only.
- 288: `wt` runs `sync` again at the same `at`. wt now holds only c0020, beaten at `at`, so it is not due. No entry has a changed stamp, so nothing is printed. Line 294 fails for the implementation the Design prescribes.

The mutant "silent second prep" is still caught at line 299, so the case adds nothing there. It only pins the notice at a place the Design never puts it.
Critique: this is the defect lesson z-design/walk-refute-added-cases-against-the-order-of-effects was written for (review 004 F1, the same notice on the same `sync`). It came back because the round-5 answer added a `sync` to an earlier case of the same worktree. A one-time effect, asserted in a spec whose cases share worktrees, is used up by whichever case first runs a command there. The tempting fix is to swap the two cases. That works until the next answer adds a command to `wt` again.
Consequences: give each old-claimant scenario its own worktree, so no case can use up another's notice. That costs one `./zn worktree` per scenario (about a second). Each `sync` that drops an entry should also assert the notices it gives, so a notice that moves is caught where it moves.
Recommendation:
- Make the old rafting claimant a worktree of its own (`wt3`, claiming the raft in setup), so `wt` stays untouched until line 292.
- At wt3's `sync`, assert `R0020's claim was taken over` on stderr, and assert it does not name c0010.
- Keep line 294 on wt's first command.
- Replay lost.spec on a prototype autobeat stub (a few lines in `main.luau`'s dispatch: read the entries, compare with `git show origin/main:<doc>`, print, delete) before the prep commit. That is the check the lesson asks for, and it would have shown this failure.
Lesson: z-design/walk-refute-added-cases-against-the-order-of-effects, z-design/prove-specs-pass-on-a-prototype

### F2 [high] The c0265 capture's "so every host and the board see it" has no design and no criterion. The method paragraph says the board reads the beats, but the board is not touched
Where: Problem, bullet 1 (the c0265 capture's wording from #258; f0265's capture had no "board"); Design, "How the 'beat pushed to main' reading is satisfied" ("every host and the board read it with one `ls-remote` of that remote, so 'every host and the board see it' holds"); Touched modules (no `z-nile/engine/board.luau`); AC1-AC6 (none names the board); README "The board" (`./zn board` writes `.cache/board.html`, rebuilt after every publish, `land` and main-checkout `sync`: main.luau `buildBoard(mainRoot())`).
Evidence: `board.luau` builds each row from `status.effective` (board.luau:26, 169) and reads no beat, verdict or marker. Nothing in the Design changes it. After this lands, a lost claim shows `[lost 45m]` in `./zn status` and is plain `preparing` on the board. Every AC passes with the board unchanged. The method comparison has no board column either. For the ref method the board needs an `ls-remote` (and a `gh pr list`) to show anything, while for a file on `main` it would be free. That is a cost the comparison does not count.
Critique: the user's rewrite added this outcome, and the Design asserts it is met without designing it. Under the zz-review scope rule (item 11), an outcome left without a criterion is high, and it is the user's capture that the Design leaves unmet. The tempting fix is to have `buildBoard` call `ls-remote` and `gh` every time. But the board is rebuilt after every publish, and `board` is `READ_ONLY` (it runs in `.git`-less sandboxes), so a network read there adds up to 10 s to every claim. It also needs the same unknown-is-never-lost rule.
Consequences: the board takes verdicts as an optional input. The command that already judged them (`status`, `lost`, `beat`, the dispatcher's tick) can leave them in an ignored `.cache` file for `buildBoard` to read, or `./zn board` alone reads them under the `ZN_NET_SECONDS` bound. Unreadable verdicts render as today. The board then states its verdict's age, since a cached verdict goes stale.
Recommendation: design the board marker: which source, how fresh, `[lost]`/`[parked]`/`[stale?]` on the item's row, and nothing when the verdicts are unknown. Add `board.luau` to Touched modules, add an AC with a case (a fixture with a lost claim shows the marker in `.cache/board.html`; with `lsfail` the board renders as today), and add the board column to the method table. If the board belongs to c0249/c0118's redraw instead, `escalate to the user:` with the options "this issue marks the board" or "c0118 or c0249 marks it, recorded as a `Decided with the user` line". Do not drop it silently.

### F3 [high] "The takeover is recorded (c0263)" is one clause, "recorded in the claim commit subject", with no subject text and no criterion, so an implementation that records nothing passes
Where: Problem, bullet 4 (c0265 capture); Design, Assumptions, Rename ("the takeover recorded in the claim commit subject (a reader of history such as c0263 can see it …)"); Takeover (no subject named); lost.spec:240-276 (asserts stamps and beats, never the commit); Rules and mutants (no row); AC3 ("a lost claim … is taken over with a fresh stamp").
Evidence: `setStatus` publishes through `publish.commit` with today's subject. The Design names no text for a takeover subject: not the old stamp, not "took over", and not the silent minutes. No case reads `git log -1 --format=%s` on origin after the takeover. An executor who leaves the subject as it is today meets every AC and every case, and c0263 (Ticket provenance, which reads "who … delivered each layer") gets nothing to read.
Critique: the capture asks for the record, and AC3 can be met without it, so a wrong implementation passes. The tempting fix is to add a word to the subject. c0263 is captured and not designed, so the format is this issue's to fix, and a reader (c0263, a reviewer) needs a stable form.
Consequences: a fixed subject form becomes a format with one writer, in `heartbeat.luau` (zz-arch one-reader-per-format). It needs the old stamp and the verdict's silence, both of which the takeover already holds. A raft takeover writes one commit for the raft and its members.
Recommendation: specify the subject, for example `tracker: <id> preparing (took over <old stamp>, lost <n>m)`, built by a pure `heartbeat.takeoverSubject(id, oldStamp, silent)`. Add a pure case in heartbeat.spec and assertions in lost.spec's two takeover cases (`git log -1 --format=%s main` on origin names the old stamp). Add a Rules row with the mutant "today's subject kept", and add "and the takeover commit names the old claim" to AC3 in both the document and check.sh.

### F4 [medium] The old rafting claimant's refusal (lost.spec:269-271) passes only if the stamp-record check comes before `setStatus`'s member design check, an order the Design does not state; c0030 is left `design: draft`
Where: lost.spec:268 (sets `design: ready` on the raft only); main.luau:1502-1507 (a carried move returns `<t> is not design: ready …` for each target, the member c0030 included); Design, Takeover (says only "refuses only when this checkout remembers a stamp and it differs from origin's"); review-005 F2's Recommendation ("wt sets `design: ready` on the raft and c0030").
Evidence: an executor who puts the new refusal beside the other per-target checks in the loop at main.luau:1440, or after it, returns `c0030 is not design: ready …` first. Line 271's `taken over` then fails for a design-correct implementation. Put first in the callback, it passes. The mutant "record written only by `setStatus`" fails either way, but for the wrong reason (the design check), so the case does not show that the record refused it.
Critique: the spec pins an order the Design never states, and it does not isolate the rule it names.
Consequences: with c0030 ready too, the only thing that can refuse the move is the stamp record, so the order no longer matters and the mutant fails on the right assertion.
Recommendation: set `design: ready` on c0030 in wt as well. State in the Design that the stamp-record refusal is checked first in the callback, before any member check. Add the mutant "record written only by `setStatus`" to the Rules row (round 5 asked for it; F9).

### F5 [medium] `Overrides: none` still rests on E8, which tested only `setStatus`. The round-5 answer added the record to `new raft`, `fold`, `unfold` and `recombine`, and a first beat to every claim, without re-running the suite
Where: Regression guard (`Overrides: none`); E8 (unchanged: "a prep scratch edit of `setStatus` … 37 passed"); Design, Takeover (the record is now written by five more commands); First beats (every claim now also does `fetch`, `ls-remote`, `git grep` and a push); Implementation step 1 (leaves the suite run to the executor); review-005 F2's Recommendation ("Extend E8's prototype to those commands. Run c0116 (all specs) … Keep `Overrides: none` only if they stay green").
Evidence: the refute says "F2: fixed", but E8's text, its count and its scope are those of round 4. c0116's flows (a resumed `fold` that draws no new stamp, `recombine`'s two rafts sharing one stamp, `release`/`fold --force`) now meet a record and a first beat that nothing in prep has run. Neither has anything run the specs whose fixture `git` answers only named subcommands (c0117's wrapper and dispatch specs) against a claim that now runs `ls-remote` and a ref push. A red spec found there in execution is an unnamed override, which stops the raft.
Critique: z-design/confirm-overrides-with-a-suite-run. The prep has the means: a scratch edit like E8's, reverted afterwards.
Consequences: if a c0116 or c0117 spec turns red, it needs an Override line with its chore in `depends_on`, or a design change (for example, a resumed `fold` writes no record).
Recommendation: extend E8's scratch edit to the four z-raft claim paths, plus a stub first beat after every claim publish (push `refs/zn/hb/<stamp>/<now>`). Run c0116 (all), c0053, c0117 and c0040 on it, record the counts in E8, and only then keep or change `Overrides: none`. Say in the Design what a resumed `fold` (no new stamp) writes.
Lesson: z-design/confirm-overrides-with-a-suite-run

### F6 [medium] The Rules row for the nested-checkout case still claims it kills "comparing path strings", which the canonical spelling (round-5 F1's fix) no longer kills
Where: Rules and mutants, "a nested `./zn` in a protected checkout never beats | … | autobeat ignoring `guarded()`; comparing path strings"; beat.spec:193-200 (the value is now `rev-parse --path-format=absolute --git-common-dir`, which is the string any naive compare would also build).
Evidence: a mutant that compares its own `rev-parse --git-common-dir` text with the list's entries finds the fixture's entry verbatim, answers guarded, and passes the case. Round 5 offered either dropping the mutant or moving the other spelling to the checkout side (running from a symlinked path to wt, which `pickman_guarded` canonicalizes with `pwd -P`). Neither was done.
Critique: the table lists a mutant that the case cannot fail.
Consequences: none beyond the row, or one extra `zn` call from a symlink.
Recommendation: either drop "comparing path strings" from the row, or add a second call in the case from a symlink to wt (`ln -s <wt> <base>/wtlink`; run `lessons --tags` with cwd `wtlink`) and keep the mutant.

### F7 [medium] Round-5 F3 is half answered: the failed-attempt throttle still has no promoted guard, and check.sh runs the proofs on every `./zn check c0265`, the done item's included
Where: proofs/race.spec:234-274 (the only case for "a failed attempt is not retried inside the interval"); design-refute-005 F3 ("stays in the proofs because it waits on a real kill"); check.sh:15-16 (AC4/AC5 run `$HERE/proofs/…` unconditionally); zz-test/specs-never-burn-real-resources ("gated in check.sh on the sequestered path"); zz-test/proofs-hold-only-the-cases-that-wait (harvested from round 5).
Evidence: the throttle rule (the entry's epoch advances on a failed attempt, and no new attempt is made inside the interval) needs a failure, not a hang. lost.spec already has `lsfail`, which fails at once. The refute's reason applies only to the "bounded" half. After `done`, `acceptance/` is promoted, `proofs/` stays in `done/c0265/`, and nothing in the gate fails if a later change retries on every command. Also, `./zn check c0265` on the done item still runs both proofs (dispatch about 3 s, race two setups plus about 15 s of real waits).
Critique: this is the lesson this issue harvested last round.
Consequences: one more promoted case (in beat.spec, which has a worktree holding entries): `lsfail`, then a command at an epoch past the interval makes one attempt, and a second command 10 fake seconds later makes none. `lscalls` counts them. The race proof keeps only the hang.
Recommendation:
- Add that case to beat.spec with its Rules row, and leave race.spec's hang case asserting only the bound.
- Gate AC4 and AC5 in check.sh on `[[ -d $HERE/acceptance ]]` (when false, `check` prints that the proof ran before `done`).
- Split AC5's label to match.
Lesson: zz-test/proofs-hold-only-the-cases-that-wait, zz-test/specs-never-burn-real-resources

### F8 [low] race.spec builds its fixture twice, and race.spec and edge.spec carry dead fixture parts
Where: race.spec:100-147 and 149-196 (two identical setup cases, each `fakecli.new("c0265-race", …)`, which `trackerfix.new` wipes and rebuilds, and four claims); race.spec's `race` arm and c0070 claim, and its c0095/c0096/R0030 seed (used only by edge.spec); edge.spec's c0080/c0085/c0090 claims, c0090's polling `check.sh`, and its `lshang`/`pushfail`/`restamp` arms (used only by race.spec).
Evidence: the duplicate doubles the proof's setup, about 10 s for the four claims and the worktree. The dead parts were left behind when the cases moved. They cost a claim each and make a reader look for cases that are not there.
Critique: the user's rule is that tests must be fast and thorough.
Consequences: none.
Recommendation: delete race.spec's second setup case. Trim each spec's seed and shim to the cases it holds.

### F9 [low] Text left over from rounds 5 and 6
Where and evidence:
- Test plan, lost.spec: still lists "hung remote" (round-5 F6 asked for it to move to race.spec) and "fresh/inclusive" (that case was renamed, and the revive case pins the edge).
- AC3, in both the document and check.sh: "malformed beat refs and a malformed beat ref" (round-5 F6).
- AC2's label promises "--watch … ends before its bound", but beat.spec, which AC2 runs, only checks the refusal. The bound is pinned by heartbeat.spec (AC1) and race.spec (AC5).
- Rules row "takeover of an issue or a raft … the old rafting claimant (new raft) is refused too": the mutant column lacks "record written only by `setStatus`" (round-5 F2).
- The row for `recombine` and `start` does not mention `unfold`, which is now in First beats.
- The Design's `SETUP.md` NTP sentence and the zz-test "Caught only by review" line (Implementation step 5) are checked by no AC6 grep.
- Rename: the four lessons harvested since the rename carry `sources: c0265 …` but say `f0265 design review …` in their Why line (for example zz-test/proofs-hold-only-the-cases-that-wait, seed-guard-inputs-in-the-producers-spelling). One id per lesson reads better. The f0265 mentions in c0265.md:51 and c0266.md are history and correct.

Critique: z-design/restated-rules-move-together.
Consequences: none.
Recommendation: fix the Test plan and AC3 in both places, move "ends before its bound" to AC5's label (or add a case), fill in the two rows, add `SETUP.md` and zz-test greps to AC6, and settle on one id in those lessons' Why lines.
Lesson: z-design/restated-rules-move-together

### F10 [low] The Design does not say that the explicit `beat` and the dispatcher's `zn beat` child refuse in a guarded checkout, as every other publisher does through `publishing()`
Where: Design, `./zn beat` (refusals: not a claim, `--watch` without a bound); Automatic beats (only the autobeat asks `guarded(true)`); main.luau `publishing()` (`hasOrigin() and … and not guarded()`), which `status` and every claim path call.
Evidence: a `check.sh` or a spec that runs `./zn beat <id>` (or `./zn dispatch`, whose tick runs `zn beat`) in the real checkout reaches the push. The fence's pre-push hook refuses it, so nothing leaks today. But the Design relies on that hook rather than the engine's own one-answer guard, which zz-test's "Caught only by review" list treats as review territory.
Critique: one rule for every publisher keeps the guard where it acts.
Consequences: `beat` in a guarded checkout says `not publishing: …` (guarded's own text) and exits 1. The dispatcher already ignores a refused beat.
Recommendation: have `beat` start with `publishing()` (or `guarded()`), state it in the Design, and add one line to the nested case in beat.spec: `beat c0010` with the appended fence list fails and leaves origin's beats unchanged.

## Candidate lessons (for the lead)
- z-design: **a spec whose cases share a worktree asserts a one-time effect only on that worktree's first command, or gives the scenario its own worktree**, because c0265 review 006 F1 found a `sync` added in round 5 used up the notice a later case asserted (the same defect as review 004 F1, one case further away). Check: for each one-time effect a case asserts (a notice, a dropped entry, a first beat), which earlier case already ran a command in the same checkout?
- z-design: **an outcome a capture rewrite adds is listed and given a criterion in the same round the rewrite is merged**, because c0265's #258 rewrite added "the board see it" and "the takeover is recorded", and the Design claimed both covered with no case. Check: diff the old and new capture, and does each added clause have a Design line and an AC?

Verdict: changes

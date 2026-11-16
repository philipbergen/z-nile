# Review 018: c0265 (design mode)
Inputs: prep head 1f9ce046 (`tracker: prep c0265 answer discard review round 3`). This is one more round after round 3 of the second restarted count, which the user asked for.
- Read: c0265.md, check.sh, design-review-015/016/017 and design-refute-015/016/017, the diff `ae285d5e..1f9ce046`, all five acceptance specs, both proofs and the prototype.
- This round changed discard.spec, beat.spec, heartbeat.spec (the suffix line), check.sh (the AC6 label) and c0265.md. The merge f532fd0f brought only other items' captures and spend files: no engine file or spec loader changed.
- Engine read: `cmd.worktree` (main.luau 3692-3753), `flags` (775), `setStatus`'s memory write (1572-1591), `rememberClaim`/`claimFile` (380-401), `reapRun` (5730-5955), `cmd.reap` (5959), `READ_ONLY` (5989), `reap.scope` (reap.luau 416), dispatcher.luau 811 and 1658 (the `prep-<slug>` derivation), `trackerfix.stub` (trackerfix.luau 109: `slug: {title}`).
- Promoted spec read: `tests/acceptance/c0005/worktree.spec.luau` (190, 228-246, 356-376, 436).
- Lessons: `./zn lessons --when design --full` and `--skill zz-review --full`.
- Capture: as in rounds 015 to 017, `(no capture commit: first add)` (#258). The Problem only gains `Decided with the user` lines, and every captured outcome still has a Design and a Checked criterion.

Dropped from review-017: F1, F4 and F5(a), (c), (d), (e) (answered, checked below). F2 is repeated as F1 and F2, F3 in part as F5, F6 in part as F6, and F8 in part as F7 and F9.

Replays. All runs were from z-nile, with the prototype copied to `engine/heartbeat.luau` and deleted afterwards; `git status --short` was empty afterwards.
- heartbeat.spec: 21/21 pass.
- Against the unchanged engine, each fixture spec passes only its setup:
  - discard: 1/8. Case 4 errors at `fs.removeFile(.../tracker-stamp-c0010)` because today's engine writes no stamp file. Cases 7 and 8 fail on `usage: worktree <R-id|name>`.
  - beat: 1/12
  - edge: 1/6
  - lost: 2/18
  - dispatch: 1/2
  - race: 1/5
- `./zn promote-check c0265`: OK. `bash -n check.sh`: clean.
- `git hash-object` gives `6fd10bdfa0c73e43b857b62b3f1ab603db903ec4` (proofs/dispatch) and `5ae722350d3d2bf820b4bc9b1ebaf9000c0fde09` (proofs/race). Both equal AC4's and AC5's pins.
- Git fixtures under `.cache/rev018`, deleted afterwards:
  - `git branch -m` carries a tracked branch's upstream to the new name, and `--unset-upstream` clears it: `remote after -m: origin`, `remote after unset: []`. So case 7's upstream assertion can fail.
  - A worktree stopped in a conflicted `git rebase` lists as `detached` in `git worktree list --porcelain` (used in F8).

Round-3 answers, checked:
- F1: fixed. The lookup is restricted to the family, the Regression guard names c0005, and `worktree main` is asserted refused in case 4. I walked c0005's cases "is idempotent", "resumes an existing branch", "refuses a branch checked out elsewhere", "recreates a worktree whose directory was deleted" and "rejects bad names and non-raft ids" (plain `worktree c0041` is still refused, because the id form exists only with `--takeover`). All stay green under the family rule.
- F2: not fixed (F1, F2). The by-id resolution falls back to `prep-<slug>` and so still depends on the name the old worker chose. The fixture's worktree is `prep-hello` while c0010's slug is `c0010`.
- F3: stated. The family-all-discarded rule is in the text. The row's reason does not hold (F5).
- F4: fixed. The ownership rule is stated, and case 3 refuses `prep-plain --item c0010` and keeps its branch. A mutant without the ownership rule discards `prep-plain` and fails `unrelated.ok == false`.
- F5:
  - (a) fixed: "when it has one", and case 7 asserts `branch.prep-hello-discarded-2.remote` empty. The copy really had an upstream (`cmd.worktree` 3741-3743 takes the `--track` path), and case 4's never-tracked `prep-hello` kills the "unset always" mutant.
  - (b) answered with case 8, which has its own problem (F2).
  - (c) fixed: case 4 removes `tracker-stamp-c0010`. `setStatus` today writes `tracker-claim-c0010` with the stamp (main.luau 1582), so the fallback finds S1, and a stamp-file-only mutant refuses with "use --item".
  - (d) fixed: beat.spec's new case (walked below).
  - (e) fixed: `{ "prep-xy-1" } → "prep-x-1"` fails for a prefix-matching `nextSuffix`.
- F6: partly. Nine rows were added. The dispatcher's takeover-before-step rule still has none (F6), and two of the new rows cannot fail or give a reason that does not hold (F4, F5).
- F7: fixed in the text, but the case added runs the reaper with its host-wide default scope (F3).
- F8: `release` added; `nextSuffix` in the signature block; 21 pure cases; AC6 greps z-raft; `--adopt` on landing day; `git log --oneline` subjects. The suspended dispatcher was declared intended, for a reason that does not hold (F7). The broken bold markup from review 017's F3 note is still there (F9).

Fixture walk, against a correct implementation of the stated design:
- discard.spec:
  - Case 1 (setup): passes.
  - Case 2: passes.
    - The live refusal: S1's last beat is T0, so silent is 60 s.
    - `prep-fresh` is created by the no-worktree path.
    - By id, c0020 resolves to `prep-c0020`: no memory holder, slug `c0020`. It is created with `.cache/fresh`.
    - `twice` resolves to the same name and finds it fresh at age 0, so it is refused.
  - Case 3: passes. It is parked by the PR title, gets `no heartbeat verdict` under ghfail, `prep-fresh` is refused as fresh before step 2, `prep-plain` is refused with `--item`, and `--item c0010` is refused by ownership.
  - Case 4 passes up to and including line 158, then fails at line 160 (F1).
    - Up to line 158: the fallback finds S1, which is lost at LATE. `nextSuffix` gives `-1` and the branch is renamed (no upstream to unset). The copy is made by `branch --track` from `origin/prep-hello`, so HEAD is the pushed tip. The note carries `?? pickman/dirty.txt` and `unpushed work`, the lookup returns `prep-hello-1`, and the by-name second taker is refused as fresh.
    - `byIdTwice` (line 159): no non-discarded worktree remembers c0010. The copy is fresh and so has no memory, and `prep-hello` is discarded. So the id resolves to `prep-c0010`, which has no worktree, and the Design creates it. The result is exit 0, where the spec expects `fresh`.
  - Case 5: passes. The guard comes before the autobeat, `reap` is exempt, and `was discarded` is absent from reap's stderr.
  - Case 6: passes. The claim in the copy is the takeover of S1 at LATE, `fresh` goes, and busy prints `prep-hello-discarded-1`.
  - Case 7: passes.
    - By id: `prep-hello-1` remembers S2, which matches main.
    - S2 is lost at LATE + 2700, because its first beat is dated LATE by `ZN_NOW`.
    - `taken` = {dir `prep-hello-1`, branch `prep-hello-discarded-1` → `-1`}, which gives `-2`.
    - The upstream is unset, and the lookup returns `-2`.
  - Case 8 passes only if the by-id form takes over `<id>` itself when the resolved worktree remembers nothing. The Design's step 2 does not say so, and literally it refuses with "use --item" (F2).
    - Case 8 runs at LATE + 1800, earlier than case 7's LATE + 2700. Nothing in the fixture depends on that order (no throttle entry or beat is involved).
  - Mutants killed: every one review 017 listed, plus: upstream kept, unset without an upstream, marker never expiring, stamp-file-only memory, `--item` without ownership, reaper refused, and `worktree main` returned.
  - Mutants that survive: "an entry left to revive the claim" (F4).
- beat.spec's new case: passes.
  - Main adopts S1 without writing `tracker-stamp-c0095`.
  - wt's autobeat at T0+1700 meets main's newer sha. That is a `stale info` rejection from a co-beater, retried silently. The give-back then drops `hb/S1` and the memory.
  - The re-claim draws S2 and writes its first beat at T0+1800, and main's `--adopt` at T0+1900 beats S2.
  - The "main writes memory" mutant fails the `isFile` assertion directly.
  - `second ~= first` fails once in 13,824 runs, by stamp collision: negligible.
- lost, edge and both proofs are unchanged since review 015 and replay the same as in review 017. I checked them against this round's main-adoption rule: edge's create-only race (188) and lost 334/379 adopt from main and expect origin's current stamp, so they agree with "main writes no memory". No case expects main to refuse after a takeover.
- check.sh: syntax clean, both pins equal `git hash-object`. AC7 runs discard.spec only, AC2 beat.spec, and AC6 now greps `--takeover` in z-raft as well.

### F1 [high] (repeat of review-017 F2, part 2) The by-id second taker is not refused while the copy is fresh: the id resolves to `prep-<slug>`, a name that has no worktree, so a correct implementation fails discard.spec line 160
Where: Discard and recover, the by-id paragraph: "the branch of the non-discarded worktree whose claim memory names the id …, else `prep-<slug>` for an issue … and the raft branch for a raft; with no worktree on the host it creates that name, marked fresh". Step 1: fresh is "removed when it gets claim memory". discard.spec 159-161. Row "the by-id takeover resolves the id to a branch…".
Evidence:
- `trackerfix.stub` writes `slug: {title}`, so c0010's slug is `c0010` and its fallback branch is `prep-c0010` (dispatcher.luau 811 and 1658 derive it the same way). The fixture's worktree is `prep-hello`, on purpose, to prove that the claim finds it.
- After case 4's takeover there are three candidates, and none qualifies:
  - `.worktree/prep-hello` is discarded and so never a candidate.
  - `.worktree/prep-hello-1` is fresh and therefore has no memory.
  - `prep-plain`, `prep-fresh` and `prep-c0020` remember nothing about c0010.
- So the id resolves to `prep-c0010`. The family has no worktree, so the Design creates `.worktree/prep-c0010` and exits 0.
- `t.expect(byIdTwice.ok).toBe(false)` then fails for an implementation that follows the text. The case passes only for one that breaks the text, by taking the discarded worktree as a holder.
- Rafts hit the same hole. A rafting worktree is `raft-<slug>`, but the by-id fallback is the raft branch. A second `--takeover R0010` while the rafting copy is fresh would therefore create the execution worktree `R0010`.
Critique: this is the fourth round with a hole in how a takeover finds the worker's checkout: by name in 015 and 016, by id in 017, and now by id again. The fallback name answers "where would a dispatcher have put it". It does not answer "who is taking this over right now", and that is the question the fresh guard asks. The tempting fix is to rename the fixture's worktree `prep-c0010`. That makes the spec pass and hides the hole for every worktree not named `prep-<slug>` (rafting worktrees, hand-named ones). That is exactly what the by-id form claims to cover ("it does not depend on a name the old worker chose").
Consequences: the takeover needs a record, at the copy, of which claims it is taking over. Once the fresh marker names ids, it is a second per-checkout record, so:
- it must never count as claim memory (the stamp-check backstop and `--adopt`'s refusal read only `tracker-stamp-*`/`tracker-claim-*`);
- it must still be removed when memory arrives;
- the resolution needs an order when a live memory holder and a fresh holder both name the id.
Recommendation:
- `.cache/fresh` records `<epoch> <id> …`: the ids the creating takeover is taking over (the old worktree's remembered claims, `--item`, or the by-id `<id>`). No id is recorded when a by-name takeover finds no worktree.
- The by-id resolution, in order:
  1. a non-discarded worktree whose memory names the id and matches main's stamp;
  2. a non-discarded worktree whose fresh marker names the id (step 1 then refuses it while young);
  3. the fallback name.
- Step 2 reads a fresh worktree's ids as its claims. That also answers F2.
- Say that the marker is not claim memory.
- Keep discard.spec 159-161 as written, and add a row for "a fresh marker names its ids".
- The resolution yields a family name, not only a branch: a memory holder `.worktree/prep-hello-1` belongs to the family `prep-hello`, and a raft branch to `R0010`. Say it.
Lesson: z-design/trace-every-way-code-runs

### F2 [medium] The by-id form has no source for its claims when the resolved worktree remembers none, so discard.spec case 8 passes only on a reading the Design does not state
Where: Step 2: "the claims that worktree remembers (`.cache/tracker-stamp-*`); for a raft name, the raft's own claim; otherwise `--item <id>` names it … None found: it refuses and says to use `--item`". The by-id form "runs the by-name steps on it". discard.spec 219-223.
Evidence:
- Case 8 runs `worktree --takeover c0020` at LATE + 1800. It resolves to `prep-c0020`, created by case 2's by-id path with `.cache/fresh` (epoch LATE, now expired) and no memory.
- In step 2 there is no remembered claim, the name is not a raft, and there is no `--item`. The steps as written refuse with "use --item", and `must(r, …)` fails.
- The case passes only if the by-id `<id>` stands in for `--item <id>`. The Design never says it does, and the ownership rule (`prep-c0020` is c0020's own branch) would then have to apply to it too.
Critique: the by-id form was added to answer review 017 F2 with "runs the by-name steps", but the by-name step 2 was written for a worktree that carries its own memory.
Recommendation: state that the by-id form's `<id>` is taken over as `--item <id>` is, ownership rule included, when the resolved worktree remembers no claim. With F1's fix, the fresh marker's ids are the claims. Say which wins when a worktree remembers other claims as well (take them all, as step 2 does now).
Lesson: z-design/spec-design-correspondence

### F3 [medium] discard.spec's new `reap --quiet` runs the reaper with its host-wide default scope from inside a spec run, where the codebase makes the reaper a no-op
Where: discard.spec 182-184; main.luau 5959-5974 (`cmd.reap`) and 5800-5810 (the scope); reap.luau 410-427; the zz-test skill's reaper paragraph: "Call sites: `--auto` at the start of the gate and `./zn sync` (quiet, does nothing in a check run…)".
Evidence:
- Only the `--auto` path asks `guarded(true)`. A plain `reap --quiet` goes straight to `reapRun`.
- With no `--root`, `reap.scope` adds the root the fixture's git common dir resolves to. It also adds `{temp}/pickman-run.` and `{temp}/pickman-guard.`, the runner's temp folders for every run on the host, and `/private/tmp/claude-<uid>/<slug>`.
- So the case stops any orphaned or marked process working in any spec run's temp folder on the machine, including the real repository's gate running in parallel. Today's processes and their ages decide what it kills.
- reap.luau 412 says an explicit root "keeps the end-to-end check safe"; the c0077 reaper case uses one.
Critique: the case only needs "the guard lets `reap` through". Running a live, host-scoped reaper to prove that reaches outside the fixture. The jail does not obviously stop it: signals are not file writes.
Recommendation: make the line `reap --dry-run --root <h.f.base>`. It still exercises the guard's exemption and kills nothing outside the fixture. The assertion stays "was discarded" absent; also assert `r.code ~= 1` or that the dry run's own output appears, so a refusal without the text cannot pass.
Lesson: zz-arch/every-command-effects-name-the-check-flows

### F4 [medium] The new row "the discard deletes the old worktree's beat entries…" lists a mutant no assertion kills
Where: Rules and mutants row 272 (mutant "an entry left to revive the claim", case "the old process that wakes up… (reap)"); Design step 3: "The old worktree's `.cache/tracker-beats/*` entries are deleted by the discard".
Evidence:
- Case 1's claim writes `.cache/tracker-beats/c0010` in `prep-hello`: the throttle entry is written whether or not the first beat succeeds.
- No case reads that file after the takeover. Case 5 asserts only the refusals, the marker and reap. So an implementation that leaves the entry passes all eight cases.
- The row's parenthesis accounts only for the running loop.
Recommendation: in case 4, after the takeover, assert `fs.isFile(dir(NAME) .. "/.cache/tracker-beats/c0010") == false`. It can fail, because the entry exists before. Keep the loop part reasoned, as the row says.
Lesson: zz-test/no-vacuous-pass

### F5 [medium] (repeat of review-017 F3, in part) The row for "a lookup whose family is all discarded creates the next numbered name" gives "a raft fixture is too costly" as its reason, but that rule needs no raft
Where: Rules and mutants row 273; "Looking a worktree up by name": "When the family holds only discarded worktrees … the lookup creates `<name>-<n>` with the next free number".
Evidence:
- The rule is about the family, not about streams. discard.spec reaches that state cheaply after case 7: `git worktree remove --force` the copy `prep-hello-2` in the fixture, and the family holds only the discarded `prep-hello` and `prep-hello-1`.
- `worktree prep-hello` must then print `.worktree/prep-hello-3`:
  - `taken` holds the directory `prep-hello-1` and the branches `-discarded-1` and `-discarded-2`;
  - the local `prep-hello` still exists, so `worktree add <path> prep-hello` works;
  - the old paths keep refusing.
- Today's code returns `.worktree/prep-hello` by path (main.luau 3726), the discarded checkout. That is exactly the "old path reused" mutant the row lists.
- The `ws-` discard by a raft takeover and the dispatcher's lookups (854, 1636) can stay reasoned, as the row says.
Recommendation: split the row. Make the family-all-discarded lookup a discard.spec case (case 7's tail, or a ninth case) and keep the raft-only parts reasoned.
Lesson: z-design/reasoned-rows-claim-testable-reasons

### F6 [medium] (repeat of review-017 F6, in part) The dispatcher's takeover before a step on a lost claim, and its `questions.md` stop when the claim is parked or unknown, still have no row
Where: The old process: "it does not reuse an old worktree for a step on an item whose claim is lost: it runs `./zn worktree --takeover <id>` first (and stops with a `questions.md` when the claim is parked or its verdict unknown)". Refute 017: "F6: fixed: a row for each rule named."
Evidence: `awk 'NR>=200 && NR<=277' c0265.md | grep -n -i "questions.md\|takeover <id>\|before a step\|suspended\|own worktree"` finds only row 233 (parking by `questions.md`). Neither the dispatcher's takeover-before-step rule nor this round's new suspended-dispatcher rule (F7) has a row.
Recommendation: add one row each. Mark them reasoned, with the reason review 017 gave: a dispatched step on a lost claim needs a model step. Point at the pure `canTakeOver` and at the dispatcher's code path for code review.
Lesson: z-design/spec-design-correspondence

### F7 [medium] "A dispatcher suspended past the limit discards its own worktree (intended …: a beat would otherwise revive a claim nobody was working)" contradicts the design's own "a beat revives a lost claim", and its reason is false
Where: The old process: "**A dispatcher that was itself suspended past the limit** and finds its claim lost discards its own worktree before its next step (intended: … a beat would otherwise revive a claim nobody was working)". lost.spec "a beat revives a lost claim". The autobeat: "A session that keeps working keeps its claim alive…".
Evidence:
- An interactive session that sleeps for 20 minutes, wakes, and runs any `./zn` command in its worktree beats and revives its own lost claim, because nobody took it over and the stamp is still its own. That is the pinned "a beat revives" rule.
- The same situation under the dispatcher runs `--takeover` on itself instead:
  - it moves its unpushed commits and dirty files into a discarded worktree;
  - it continues from the pushed branch with a new stamp;
  - it leaves the headless next step to notice a cherry-pick note, which no step reads.
- The claim was not "nobody was working": the dispatcher was mid-chain.
- The user's discard rule is about a takeover ("That way a process that wakes up knows it has been discarded"). Here nobody took over, so this extends the rule without a user line.
Critique: review 017 F8 asked whether it is intended. The answer says it is, but the reason it gives does not hold, and nothing pins or vets it.
Consequences: telling "my own lost claim" from "another worker's" needs a fact the dispatcher already has: the step worktree's memory equals main's stamp, and no `.cache/discarded` is present.
Recommendation:
- A dispatcher whose step worktree remembers the stamp main still shows beats it (`--adopt --stamp`) and carries on, as any owner's autobeat does.
- It runs `--takeover` only when its memory differs from main's stamp (someone took over, so its worktree is already discarded and the guard stops it) or when it has no worktree for the item.
- Add the row (F6). If the self-discard is kept, list it under "Readings … for veto" with its cost (unpushed work moved aside, a new stamp).
Lesson: z-design/liveness-names-held-not-worked-states

### F8 [medium] The branch-based family lookup no longer finds a worktree that is detached (mid-rebase, `git checkout <sha>`), which today's path match returns; z-run and the dispatcher `cd` through it
Where: "Looking a worktree up by name … returns the worktree of the `<name>` family that has the branch checked out … When the family holds only discarded worktrees … creates `<name>-<n>`". main.luau 3725-3728 (today: `if w.path == path then print(path)`).
Evidence:
- Fixture output above: a worktree stopped in a conflicted rebase is `detached` in `git worktree list --porcelain`.
- Under the Design, `./zn worktree R0010` from the lead's own conflicted rebase finds no family member on `R0010-<slug>`. The family is not "only discarded", so no rule applies, and the creation path's `git worktree add .worktree/R0010 …` fails on the existing path.
- Today it prints the path. The same happens for a worktree switched to another branch.
- No promoted spec pins the case: c0005 436 makes a detached worktree but runs only `worktree-prune`, so the gate would not catch it.
- This hole predates this round. It came with the branch-based lookup (round 015's answer), and the family rule kept it.
Recommendation:
- Order the lookup: (1) a non-discarded family member that has the branch; (2) `.worktree/<name>` itself when present and not discarded, whatever its HEAD (today's rule); (3) the family-all-discarded rule; (4) create.
- Add a discard.spec line: `git checkout --detach` in `prep-hello-2` (fixture git), then `worktree prep-hello` still prints `prep-hello-2`. Re-attach it afterwards.
Lesson: z-design/confirm-overrides-with-a-suite-run

### F9 [low] Leftovers
- Step 3 says `nextSuffix` takes "the smallest `n >= 1` with no directory and no local branch of that name". The signature comment (new this round) builds `taken` from the directories `<name>-<n>` and the branches `<branch>-discarded-<n>`. Make step 3 say the latter. For a raft the branch (`R0010-demo`) differs from the name (`R0010`).
- The lease paragraph still has the broken bold markup (`**writes the memory in the adopting **worktree**`, noted in review 017). It also says twice that the dispatcher's `--adopt --stamp` and a main-checkout `--adopt` write no memory.
- The Test plan's discard line does not list this round's cases: by id with no worktree, the by-id second taker, `--item` ownership, the stamp-file fallback, `worktree main`, `reap`, the upstream and the expiry.
- harvest.md's review-017 note maps both of the reviewer's candidates to `zz-arch/every-command-effects-name-the-check-flows`. That file gained no note (its only c0265 line is round 003's), and its check question ("which check.sh files… run this command in the real checkout") catches neither candidate: a guard exempting cleanup, or a widened lookup keeping old refusals. Add notes where they fit, or new lessons.
- `--takeover` is both valued (`worktree --takeover c0010`) and bare (`worktree prep-plain --takeover --item c0010`). With today's `flags` (main.luau 800-803), a valued `--takeover` would swallow `--item`. Write the grammar: it takes a value only when no name is given and the next argument is an item id.

Product decisions: one slipped in. The suspended dispatcher discarding its own worktree with no takeover (F7) extends the user's discard rule, which is about a takeover, without a user line and without being listed for veto. Nothing else changes a user decision. Readings (4) and (5) are listed with their alternatives.

Convergence: this round has 9 findings: 1 high, 7 medium and 1 low. 7 of them (F1 to F7, the high included) are defects in what was added to answer review 017. F8 predates this round, and F9 is mixed (3 of its 5 items were added this round). Most of this round's problems are spec hygiene, such as rows whose case cannot fail and a reaper scope. The exception is the high: for the fourth round running it is in how a takeover finds the worktree to take over, and patching the lookup a fourth time is not converging. F1 asks for a recorded fact (the fresh marker names its ids) instead of another derived name.

Lesson candidates (for the lead):
- z-design: "a fallback name derived from the item (`prep-<slug>`) cannot stand in for the record of who holds or takes it; a guard keyed on that name misses every checkout named otherwise". Check: "does the fixture name the checkout differently from the derived name, and does the guard still fire?"
- zz-test: "a spec that only needs a cleanup command not to be refused runs it in its dry-run form with an explicit fixture scope". Check: "does any case run `reap` (or another host-scoped cleaner) without `--root` and `--dry-run`?"

Token usage: not visible to the reviewer.

Verdict: changes

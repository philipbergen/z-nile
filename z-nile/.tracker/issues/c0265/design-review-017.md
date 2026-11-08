# Review 017: c0265 (design mode)
Inputs: prep head bc79214c (`tracker: prep c0265 answer discard round 2`). Round 3, the final round, of the second restarted count. I read c0265.md, check.sh, design-review-016 and design-refute-016, the diff `6eb0d4f7..bc79214c`, all five acceptance specs, both proofs and the prototype.
- This round's diff touched only discard.spec, check.sh (AC7's label) and c0265.md. beat, lost, edge, heartbeat, both proofs and the prototype are unchanged since review 016.
- Engine code read: `cmd.worktree` (main.luau 3692-3753), `flags` (775), `READ_ONLY` and the dispatch (5976-6008), `rememberClaim`/`claimFile` and their callers (380-400, 1313, 1582, 1767, 1874, 1999), dispatcher.luau `worktree()` (222), the step worktrees (804-815), `streamWorktree` (854), `facts` (1625-1660), the root `zn` script, scripts/hooks/session-end.sh and `.claude/settings.json`'s hook commands.
- Promoted spec read: `z-nile/tests/acceptance/c0005/worktree.spec.luau` (238-246).
- Lessons: `./zn lessons --when design --full` and `--skill zz-review --full`.
- Capture: `./zn capture c0265` is `(no capture commit: first add)` (#258), as in rounds 015 and 016. The Problem only gains `Decided with the user` lines, and every captured outcome still has a Design and a Checked criterion.
Dropped from review-016: F1, F6 (answered, checked below). F2, F3, F4, F5, F8 and F9 are partly repeated as F4, F5, F2, F3, F5 and F8.

Replays. All runs were from z-nile, with the prototype copied to `engine/heartbeat.luau` and deleted afterwards. `git status --short` was empty afterwards.
- heartbeat.spec: 21/21 pass.
- Against the unchanged engine, each fixture spec passes only its setup and fails every other case:
  - discard: 1/7. Case 7 fails on `usage: worktree <R-id|name>`, because `flags` makes `--takeover` a valued flag and so consumes `c0010`. The by-id form parses as the Design writes it.
  - edge: 1/6
  - beat: 1/11
  - lost: 2/18
  - dispatch: 1/2
  - race: 1/5
- `./zn promote-check c0265`: OK. `bash -n check.sh`: clean.
- `git hash-object` gives `6fd10bdf…` for proofs/dispatch and `5ae72235…` for proofs/race. Both equal the hashes AC4 and AC5 pin.
- E8: the 53 files E8 names (c0116, c0053, c0117, c0115, c0120, c0005 and the four tooling globs) do count 53. I re-ran them on the unchanged engine as a count check: see the last line of this review. The scratch edit itself is not recorded, so it cannot be replayed.
- Git fixture under `.cache/rev017` (deleted afterwards), output below. It shows that a branch made by `cmd.worktree`'s `--no-track` path and pushed with an explicit refspec has no upstream, and that `git branch --unset-upstream` then exits 128:
  ```
  remote after --no-track: []
  remote after explicit push: []
  fatal: branch 'prep-x-discarded-1' has no upstream information
  unset-upstream exit: 128
  ```

Round-2 answers, checked:
- F1: fixed. The Problem's gloss (line 34), the Assumptions bullet (51) and the review-count note (146) state the numbered-copy reading. Readings (4) and (5) list the branch-rename and the copy-from-pushed choices, each with its alternative.
- F2: partly fixed.
  - The `tracker-claim-<id>` fallback is stated (53). It is correct: every `rememberClaim` caller writes a stamp.
  - The landing-day limit is said.
  - Line 53's "`--item <id>` also needs the lost verdict, so it cannot discard a live worker's worktree" is not true (F4).
  - The fallback has no case (F5).
- F3: fixed in the text: one rule, a worktree `--adopt` writes the memory. The bold markup of that sentence is broken (`**writes the memory in the adopting **worktree**`). The case review 015 F2 and review 016 F3 asked for is still missing (F5).
- F4: fixed. The fresh marker carries its epoch, the no-worktree path writes it, and case 3 refuses `prep-fresh` as fresh and `prep-plain` for `--item`. The expiry has no case (F5).
- F5: the by-id form, the `ws-` discard and the dispatcher's takeover were added. The by-id form leaves holes (F2), and the `ws-` and dispatcher paths are unspecified where they meet a discarded path (F3).
- F6: fixed. busy is asserted on `prep-hello-discarded-1`, which only the renamed branch's line prints. The note is asserted on `discarded worktree: <old path>`.
- F7: fixed in the text, but it has no row (F6).
- F8: fixed in the text. The assertion cannot fail in this fixture (F5).
- F9: partly fixed (F8).

Fixture walk, against a correct implementation of the stated design:
- discard.spec, cases 1 to 6: pass. In order:
  - Case 2: live at T0+60, then the no-worktree path creates `prep-fresh` with its marker.
  - Case 3: parked by the PR title; `no heartbeat verdict` under ghfail; `prep-fresh` is fresh at age 0 (step 1 comes before step 2); `prep-plain` has no memory, so the refusal names `--item`.
  - Case 4: lost at LATE; `nextSuffix` gives `-1`; the branch is renamed; the copy is made through `branch --track` from `origin/prep-hello`, so HEAD is the pushed tip; the note lists `?? pickman/dirty.txt` and the commit `unpushed work`; the lookup returns the copy; the second taker is refused as fresh.
  - Case 5: the guard runs before the autobeat, and `lessons`, `beat` and `status` are refused.
  - Case 6: the takeover claim in the copy removes `fresh`, and busy prints `branch prep-hello-discarded-1 changes pickman`.
- discard.spec, case 7 (by id) passes only if the lookup skips the discarded `.worktree/prep-hello`. That worktree still remembers `c0010` = S1, because memory is kept as the stamp-check backstop. The Design does not say to skip it (F2).
- Mutants killed:
  - the taker entering the old worktree;
  - a new branch name for the taker;
  - the remote rewritten;
  - a copy overwritten;
  - `settle` ignored;
  - no fresh marker;
  - a command run in a discarded worktree, the beat included;
  - the work deleted;
  - busy skipping the discarded branch;
  - a by-name (`prep-<slug>` = `prep-c0010`) lookup for the by-id form.
- Mutants that survive:
  - the upstream kept;
  - the fresh marker never expiring;
  - no `tracker-claim` fallback (F5).
- beat, lost, edge and both proofs are unchanged and pass as walked in reviews 015 and 016. lost.spec takes over with `status` in `wt2` and never runs `--takeover`. That still agrees with the Design, because a `status` takeover stays allowed and the discard is the skills' route.

### F1 [high] The branch-based lookup "wherever it is" turns c0005's promoted "worktree refuses a branch checked out elsewhere" red, and Overrides says none
Where: Discard and recover, "Looking a worktree up by name": "`./zn worktree <name>` … returns the worktree that has the branch checked out, wherever it is (`R0010`, then `R0010-1`), and never a discarded one". Regression guard, `Overrides: none`.
Evidence: `z-nile/tests/acceptance/c0005/worktree.spec.luau:238-246` runs `tr(main, { "worktree", "main" })` and expects `ok == false`, `already used by worktree at` on stderr, and no new worktree. Today the refusal is `cmd.worktree`'s `elseif w.branch == branch then fail(...)` (main.luau 3729). The Design's sentence turns exactly that branch match into a return. The natural implementation (`for w in worktrees() do if w.branch == branch then print(w.path) return end end`) prints the main checkout's path for `worktree main`, and c0005's case fails. That spec is in E8's run set, but E8 did not implement the lookup, so E8 could not catch this. The Regression guard does not name it.
Critique: the intent, the copies of `<name>`, is in the parenthesis, but "wherever it is" is the rule an executor codes. The tempting fix is "except the main checkout". That still returns any other worktree whose branch happens to be `<name>`, for example a `start`-era worktree at a path outside the family.
Consequences: when the lookup is restricted to the family, the path `.worktree/<name>` can be occupied by a discarded worktree while no family member holds the branch: the `ws-<issue>` streams after every raft takeover, or a copy removed by hand. That case then needs a rule (F3).
Recommendation:
- Restrict the lookup to the `<name>` family: `.worktree/<name>` and `.worktree/<name>-<n>` (n numeric), skipping any with `.cache/discarded`. A branch checked out at any other path keeps today's refusal.
- Name `c0005/worktree.spec` ("refuses a branch checked out elsewhere", "is idempotent") in the Regression guard as kept.
- Add a discard.spec line after case 4: `worktree main` from the main checkout is still refused.

### F2 [medium] The by-id form `worktree --takeover <id>` is unspecified exactly where it differs from the by-name form: the discarded worktree keeps the memory, the fresh copy has none, and there may be no worktree at all
Where: Discard and recover: "The form by id finds the item's worktree by its claim (the worktree whose claim memory names the id; for a raft, its raft branch)". Step 1 (fresh). The lease paragraph: memory "ends only with its checkout (a discarded worktree)", and "the stamp check (its memory against `main`) is the backstop". The skills (z-design, z-raft) and the dispatcher use the by-id form.
Evidence:
1. **Two worktrees remember the id.** In discard.spec case 7, `.worktree/prep-hello` (discarded, `tracker-stamp-c0010` = S1) and `.worktree/prep-hello-1` (S2) both name c0010.
   - An implementation that takes the first `git worktree list` match can land on the discarded one. Its remembered claim S1 has "already ended" (origin holds S2), so step 2 lets it through and the worktree is discarded a second time, with branch `prep-hello-discarded-1-discarded-2`.
   - The case passes only if the search skips discarded worktrees, and the Design says "never a discarded one" only for the lookup by name.
2. **A fresh copy has no memory by definition.** It loses `.cache/fresh` exactly when it gains memory. So after taker A's `--takeover c0010` and before A claims, taker B's `--takeover c0010` (the dispatcher and an interactive z-design both follow the by-id instruction) finds no live memory holder. B then either:
   - re-discards the old worktree (which still holds S1, the stamp origin still shows, so the claim is still lost); or
   - finds nothing, and "creates `<name>`", but no `<name>` exists in the by-id form.
   Either way the fresh guard, which works by name in step 1, is bypassed. That is the double-taker race review 015 F5 and review 016 F4 closed for the by-name form.
3. **No worktree holds the claim** (it was removed, or the claim was made in the main checkout): the by-id form has no rule.
Critique: this is the third round with a hole in how the takeover finds the old checkout (by name in 015 and 016, now by id). The by-id search answers "who held it", but the fresh guard and the copy's name are keyed by branch.
Consequences: resolving id → branch first gives one path for both forms. The branch is the non-discarded memory holder's branch, else `prep-<slug>` for an issue (as dispatcher.luau 1655 already derives) and `raftBranch` for a raft. The by-name steps 1 to 4 then run on it, the fresh check included. A memory holder whose remembered stamp differs from origin's, while another worktree's memory matches origin's, is not a candidate.
Recommendation:
- State that resolution, and that discarded worktrees are never candidates.
- Add discard.spec cases:
  - in case 4, a by-id second takeover (`worktree --takeover c0010`) is refused as `fresh` while the copy is fresh;
  - a by-id takeover of a lost claim with no worktree on this host creates `prep-<slug>` with its marker.
- Add a row for each.
Lesson: z-design/trace-every-way-code-runs

### F3 [medium] (repeat of review-016 F5, in part) A raft takeover discards the `ws-<issue>` streams at their own paths, but nothing says where the new lead's streams go, and the dispatcher still addresses streams and rafting trees by path
Where: Discard and recover, step 3: "A raft takeover discards its `ws-<issue>` stream worktrees the same way (marked, branches renamed, numbered copies not created: z-run recreates streams from the raft branch)". dispatcher.luau 854 and 1636.
Evidence:
- After the takeover, `.worktree/ws-c0040` is discarded and its branch is `ws-c0040-discarded-<n>`. The new lead runs `./zn worktree ws-c0040 --from <raft branch>` (zz-execute 2B).
  - Today's code returns `.worktree/ws-c0040`, because the path matches (main.luau 3726). That is the discarded checkout, where every `./zn` is refused, so the stream cannot run.
  - Under the Design's lookup ("never a discarded one") the path is taken and no worktree holds `ws-c0040`, and no rule says which path the new stream gets.
- The dispatcher's stream reviewer is pointed at `` `{mainRoot}/.worktree/ws-{id}` `` (854), a built path, which after a takeover is the discarded tree.
- `facts` reads a member's `raft:` from `` `.worktree/raft-{id}` `` (1636). After a rafting takeover that is the discarded copy, so the dispatcher's next-step decision reads the old worker's local state.
- No spec, row or AC covers any of this.
Critique: the earlier rounds fixed the lookup. The paths that skip the lookup are the same hole in another place.
Consequences: a discarded name's next worktree takes the next free suffix (`ws-c0040-1`, `nextSuffix`), which is what the copy rule already does. The dispatcher must then find streams through `./zn worktree`.
Recommendation:
- State it: a lookup whose family holds only discarded worktrees creates `<name>-<n>` (this also covers review 016 F9's hand-removed copy).
- Make dispatcher.luau 854 and 1636 resolve through the lookup.
- Add a row and a discard.spec case: a raft fixture with one `ws-` worktree; after `--takeover R…`, `worktree ws-<issue> --from <branch>` prints a new path, and the old path refuses with the discard notice. If a raft fixture is too costly here, the row says so and why.
Lesson: z-design/results-land-on-every-path

### F4 [medium] (repeat of review-016 F2 part 3) `--item` still discards an unrelated worktree that has no claim memory; the Design's sentence saying it cannot is wrong
Where: Discard and recover, step 2: "otherwise `--item <id>` names it". Assumptions, Landing day: "`--item <id>` also needs the lost verdict, so it cannot discard a live worker's worktree".
Evidence: `--item` is consulted only when the worktree remembers no claim. Worktrees with no memory but a live worker are common:
- a capture worktree;
- a `ws-<issue>` stream;
- `prep-plain` in discard.spec itself;
- any worktree made before this lands that holds no `tracker-claim-*`.
With c0010 lost, `./zn worktree prep-plain --takeover --item c0010` checks only c0010's verdict. It then marks `prep-plain` discarded, renames its branch `prep-plain-discarded-1`, creates `prep-plain-1`, and tells the worker there "c0010's claim was taken over", an item it never touched. The lost verdict is about the item, not about the worktree.
Critique: the check that is missing is ownership, not liveness.
Recommendation:
- Accept `--item <id>` only when the worktree's branch is the item's (`prep-<slug>` for an issue, its raft branch or `R…` for a raft, or a `ws-<member>` of that raft). Otherwise refuse, naming both, and move nothing.
- Correct the Landing-day sentence.
- Add a discard.spec line in case 3, where c0010 is lost and `prep-plain` exists: `worktree prep-plain --takeover --item c0010` is refused, and `prep-plain` keeps its branch.
- Add a row.

### F5 [medium] Round-2 rules whose assertions cannot fail, or have no case: the upstream unset, the fresh expiry, the `tracker-claim` fallback, the main-checkout adoption, and the suffix line
Where: discard.spec 134-136; Discard and recover, steps 1 and 3; Landing day; The lease and ownership; heartbeat.spec 329.
Evidence:
- (a) **Upstream.** The fixture's `prep-hello` is made by `./zn worktree`'s `--no-track` path (main.luau 3750) and pushed with `HEAD:refs/heads/prep-hello`, so it never has an upstream (fixture output above). `branch.prep-hello-discarded-1.remote` is therefore empty whether or not the takeover unsets anything, and the mutant "upstream kept" passes.
  - It also cuts the other way: `git branch --unset-upstream` on that branch exits 128. An implementation that runs the Design's step literally through `sh.git` (which fails on error) dies in case 4, so the step needs "when it has one".
  - Case 7's copy does have an upstream (`branch --track prep-hello origin/prep-hello`), so the assertion belongs there, on `prep-hello-discarded-2`.
- (b) **Fresh expiry.** "Refused while younger than `STALE`; a copy whose taker crashed … becomes takeable after the limit" has no case. "The marker never expires" passes every spec, and that mutant is the wedge review 016 F4(a) found.
- (c) **`tracker-claim` fallback.** No case: an implementation that reads only `tracker-stamp-*` passes everything.
- (d) **Main-checkout adoption writes no memory.** This is the third round without the case review 015 F2 and review 016 F3 recommended (main adopts X at S1; X is re-claimed at S2; main's next `beat X --adopt` beats S2). "Main writes memory" passes every spec.
- (e) **Suffix line.** heartbeat.spec 329's `{ "prep-x-1", "prep-xy-1" } → "prep-x-2"` still cannot fail, because `prep-x-1` alone forces `-2`. The refute leaves it to "the executor's tidy-up", but `acceptance/` is sequestered, so the executor may not edit it. Only prep can.
Recommendation:
- Say "unset its upstream when it has one", and move the upstream assertion to case 7 (`branch.prep-hello-discarded-2.remote` is empty).
- Add a case: a copy whose `.cache/fresh` epoch is older than 900 s (write it with `ZN_NOW` offset) can be taken over.
- Add a discard.spec setup variant: delete `tracker-stamp-c0010` and keep `tracker-claim-c0010`, then the takeover still finds the claim without `--item`.
- Add a beat.spec case for (d).
- Change heartbeat.spec's line to `{ "prep-xy-1" } → "prep-x-1"`.
Lesson: zz-test/no-vacuous-pass, z-design/spec-design-correspondence

### F6 [medium] The Rules and mutants table has no row for most of the round-2 rules
Where: Rules and mutants (rows 257-264); Discard and recover; The lease and ownership; The dispatcher.
Evidence: these behavioural rules in the Design have no row, so each listed mutant is neither killed nor reasoned:
- a raft takeover discards its `ws-` streams;
- the dispatcher runs `--takeover` before a step on a lost claim, and stops with a `questions.md` when the claim is parked or its verdict unknown;
- the discard deletes the old worktree's `.cache/tracker-beats/*`, and a running `--watch` or dispatcher tick stops on the marker;
- the `tracker-claim-<id>` fallback;
- the fresh marker's expiry;
- a main-checkout or `--stamp` adoption writes no memory;
- the renamed branch's upstream is unset;
- the by-id form finds the worktree by its claim (AC7 names it; no row does).
Recommendation: one row each. Name the case from F2 to F5 where one is added. Otherwise mark the row reasoned with the reason (for the dispatcher: a dispatched step on a lost claim needs a model step, so the row points at the pure `canTakeOver` plus the dispatcher code path).
Lesson: z-design/spec-design-correspondence

### F7 [medium] The discard guard refuses `reap`, so the session-end reaper of a session whose project directory is the discarded worktree is refused silently, and that session's processes leak
Where: Discard and recover, "The old process": "Every `./zn` command run in a worktree with `.cache/discarded` except the read-only set … refuses". The autobeat, by contrast, exempts `beat`, `run` and `reap`.
Evidence:
- `.claude/settings.json` runs `"$CLAUDE_PROJECT_DIR"/scripts/hooks/session-end.sh`. That script `cd`s to its own checkout and runs `./zn reap --session-end … >/dev/null 2>&1`.
- The dispatcher launches agents with `cwd` set to the step worktree (dispatcher.luau 809-815), so their project directory is that worktree. An interactive session started in a worktree is the same.
- When that worktree has been discarded (the old session is exactly the one that wakes up there), the reaper runs the worktree's engine, hits the guard, exits 1 into `/dev/null`, and stops nothing.
- `./zn run` is unaffected, because the root `zn` script handles it before the engine.
Critique: AGENTS.md's process rule relies on the session-end reaper catching what a session leaves. The guard is meant to stop work, not cleanup.
Recommendation:
- Exempt `reap` from the guard, as the autobeat does, and say so beside `READ_ONLY`.
- Add a discard.spec line in case 5: `reap --quiet` in the discarded worktree is not refused.

### F8 [low] Leftovers
- `release` is still missing from the claim-ending commands that end a checkout's memory. The lease paragraph says "`status <id> new`, `stop`, `done`". The refute says it was added, but `grep -n release c0265.md` finds it only at 125 and 222, not as an end of memory (review 014 F7, 015 F11, 016 F9).
- `heartbeat.nextSuffix` is used in step 3 but absent from the module's signature block. Its `taken` set still ignores `<branch>-discarded-<n>` branches, so a leftover discarded branch whose directory was removed makes step 3's `branch -m` fail (repeat of review 016 F9).
- The Test plan says "seventeen pure cases"; heartbeat.spec has 21.
- The skills paragraph gives z-raft `./zn worktree --takeover <R-id>`, but AC6 greps `--takeover` only in z-design and z-run.
- The Landing-day instruction "their owners run `./zn beat <id>` from their worktree" fails for a readied raft's worktree, which has no `tracker-claim`. It needs `--adopt`, as z-run's line says.
- The recovery note must list each unpushed commit's subject (the spec asserts `unpushed work`). Say `git log --oneline origin/<branch>..<branch>-discarded-<n>`.
- A dispatcher that was itself suspended past the limit, with nobody taking over, discards its own worktree before its next step, although a beat would revive the claim. Say whether that is intended. It moves its unpushed work aside for nothing.
- refute-016 F2 names the memory `.tracker/stamp`. The Design's `.cache/tracker-stamp-<id>` is right, and only the refute is wrong.

Product decisions: none slipped in. The two new readings, (4) the branch-rename and (5) the copy-from-pushed choice, are listed for veto with their alternatives and costs. Neither the dispatcher's takeover before a step nor the fresh limit (`STALE`) changes an outcome the user decided.

Lesson candidates (for the lead):
- zz-arch: "a guard that refuses every command in a checkout must exempt the cleanup that runs there (`reap`, hooks)". Check: "which commands do the hooks run in this checkout, and does the guard let them through?"
- z-design: "a lookup made to find copies must keep every refusal the old lookup had". Check: "which promoted spec asserts the old lookup's refusal (`already used by worktree`)?"

E8 count check (the 53 files on the unchanged engine): see below.

Verdict: changes

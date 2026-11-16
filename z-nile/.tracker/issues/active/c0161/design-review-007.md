# Review 007: c0161 (design mode)
Inputs: worktree prep-closure-skips-design-review at c199e8de plus its uncommitted item folder (c0161.md, check.sh, acceptance/*.spec.luau, experiments/{proto-engine,proto-fixtures,proto-skills}.patch and mutants.py, harvest.md, proposed-lessons.md, design-review-001..006, design-refute-001..006). Prototype: /var/folders/b1/97q05hyx277_zqbc5mcchvlw0000gn/T/tmp.s7xjM875fY/p (c199e8de plus the three patches; I read `preparedRead`, `refuseUnraftable`, `recordGrouped`, `originFolderFiles`, `cmd["raft-plan"]`, `new raft`'s member loop, `ready`'s member callback, the carried move's grouped check, `status.luau`'s stale message, and the skill diffs). origin/main: the brief's 0dc30738, and 3b57fe7f as the worktree's `origin/main` reads now. Lessons: `./zn lessons --when design` and `./zn lessons --skill zz-review`. Runs: one scratch spec on a `cp -c` copy of the prototype, deleted afterwards (F1). The record quote is waived: `./zn design-record` is not landed in this worktree, so this round has no `Design record:` line.
Dropped from design-review-006: F1 (review-read now asserts per id, with `planTakes`/`planSkips`. Every take checks its result: `raft:` lines and `active/` paths. N8x, N9x and N2y are rows and runner entries, and N8x and N9x die on c0950 and c0965 by reading), F3 (R0074's Theme is quoted, and step 6 and the Touched path are conditional), F4 (`hasOriginMain` guard, Usability corrected), F5 (z-ready step 2 and z-raft §1 updated and pinned, duplicate suffix gone). F2 is fixed for prepared, raftless issues and for the R0078 shape, but its rafted-member recovery does not work (F1 below).

### F1 [medium] The new recovery for a rafted member ("add the member's round there before the re-fold, so the re-fold's `grouped:` record covers it") is refused by `./zn ready`: the re-fold records `grouped:` from origin/main, not from the rafting worktree
Where:
- Design part 5, "The recovery" ("So the member's round goes into the member's folder in the rafting worktree, before the re-fold (its `grouped:` record covers reviews, so the re-fold must come after the round)").
- z-raft §2's new bullet, pinned by docs.spec (`add the member's round there before the re-fold`).
- zz-rules' Rafting bullet ("a rafted member changed inside its raft gets that round in the rafting worktree before the re-fold").
- z-design 5.3 ("a rafted member changed in its raft").
- The z-raft lesson note in proposed-lessons.md ("The round enters the member's `grouped:` record, so the re-fold must come after it").
- The refusal text ("z-raft 2 for a rafted member").
Evidence:
- `recordGrouped` (main.luau:921) hashes `originFolderFiles(store.get(id).dir)`, which is the member as it is on origin/main. A round, or an edit, that exists only in the rafting branch never enters `grouped:`, whatever order the steps run in.
- I ran a scratch spec on a copy of the prototype. Setup: prepared c0950 with an approving quoted round 001. Steps, in a rafting worktree:
  1. `new raft chore fixit c0950`. This gave `grouped: [c0950@5a98eabc70b4]`.
  2. Edit c0950's document, write `design-review-002.md` approving and quoting `./zn design-record c0950`, and commit.
  3. Re-fold. `fold R0010 c0950` refuses with "c0950 already belongs to R0010". `unfold R0010 c0950` followed by `fold R0010 c0950` succeeds, and the record is still `grouped: [c0950@5a98eabc70b4]`.
  4. Write the Theme and Order, run `status R0010 prepared` (ok), commit, and push to origin main.
  Then `ready R0010` from the main checkout prints `ready: R0010: c0950 (5a98eabc70b4 → da0d97a7b920) changed on origin/main since R0010 grouped it: z-raft drops it (./zn unfold R0010 <id>) or folds it again with a new coherence review`.
- c0161's own check passes in that run: `preparedRead` sees round 002 quoting the edited record. The documented path fails on the c0116 `grouped:` check, and c0161's text promises it doesn't ("so the re-fold's `grouped:` record covers it").
- No case walks this path. review-read's recovery cases push round 002 straight to origin with `elsewhere`/`push`, never through a rafting worktree and a re-fold. So the specs are green while the documented sequence fails.
- The pre-existing lesson z-raft/rafted-member-changes-stay-in-the-raft ("fold it again at the end so `grouped:` matches") has the same flaw. A plain `fold` of a member refuses, and an unfold+fold records origin's old hash. c0161 extends that path instead of checking it.
Critique: lesson zz-arch/refusals-are-gate-checks ("does the recovery work while the tool refuses?") and z-design/spec-design-correspondence. This is the second round in which the recovery for the rafted-member trigger is wrong. Round 6 found it unwritten, and round 7 finds it written but refused. The tempting fix is to reword the order of the steps. No order works inside one rafting PR, because `grouped:` only ever sees origin.
Consequences:
- A recovery that works within the engine as it stands takes two landings. Option (a):
  1. The rafting PR (or a prep PR) lands the member's edit and its approving round 002.
  2. `ready` then refuses on `grouped:`, as above.
  3. A second rafting worktree runs `unfold` + `fold` (which now records origin's edited hash), plus a raft-mode coherence round when the raft has several members, then `status <R-id> prepared`, and lands.
  4. `ready` takes it.
  That adds a PR to every in-raft member fix, and the lesson's "fix in the raft" advice becomes "fix, land, re-fold, land".
- Option (b): make `fold` record a member's `grouped:` from the rafting worktree when this checkout claims the raft. That changes c0116's "as on origin/main" rule, which the carried move's `regrouped(map, originHashes)` and `ready` rely on. It is outside the Touched modules and is a decision for the lead or user.
- Either way, z-raft §2, zz-rules, z-design 5.3, the refusal's "z-raft 2" pointer, the docs.spec pins and the proposed lesson note change together.
Recommendation:
- Choose between (a) and (b), and record the choice. For (a), rewrite the rafted-member sentence in all five places to the two-landing order, and re-pin it in docs.spec. Leave `recordGrouped` as it is.
- Add a review-read case that walks the documented path end to end through a rafting worktree: new raft, member edit, round 002, re-fold, `status <R-id> prepared`, land. For (a), assert that `ready` refuses on `grouped:`, not on the record. Then add a second rafting with unfold+fold, land, and assert that `ready` takes the raft (the member in `active/`).
- Correct the z-raft note in proposed-lessons.md, and report the pre-existing flaw in z-raft/rafted-member-changes-stay-in-the-raft. A plain re-fold refuses "already belongs", and an unfold+fold records origin. The lead captures it, or fixes the lesson in this prep.
Lesson: zz-arch/refusals-are-gate-checks, z-design/spec-design-correspondence

### F2 [low] Design part 5 and a case title say round 002 lets `new raft` take a stale issue, but the case runs only `fold`
Where: Design part 5 ("a case in `review-read` pins that an approving `design-review-002.md` quoting the edited record lets `new raft`, `fold` and `ready` take the issue"). Rules and mutants row "`new raft`/`fold` and `ready` then take it". review-read.spec:238-256 ("…makes a stale issue current for new raft and fold").
Evidence: the case runs `fold R0960 c0951` and the forged-round refusal for c0954. No `new raft` call follows round 002. Because `preparedRead` is one shared function, N2y is still killed through `fold`. So the gap is a sentence that overstates the spec, not a fakeable criterion.
Recommendation: either add a `new raft` take of a stale-then-recovered issue (one more fixture issue, since c0951 is folded by then), or reword the Design sentence, the row and the case title to `fold` and `ready`.

### F3 [low] Shared state has drifted: R0071 is no longer active
Where: Shared state, the bullet "R0068, R0070, R0071, R0073, R0075 and R0078 are active on `origin/main`".
Evidence: at 0dc30738 R0071 and c0191 were in `active/`. Since then `659f8b75 tracker: stop R0071` and `8ab88a88 tracker: unfold from R0071 (claim)` landed. At 3b57fe7f R0071 is `preparing-otter-lynx-marble` in the backlog, and c0191 is `prepared` there. c0191 touches `main.luau` and four of the same skills, and it may now be redesigned.
Recommendation: update the bullet (R0071 stopped; c0191 back in the backlog and possibly in redesign) and re-read c0191's document when it next changes. Nothing else changes, because the merge rule (disjoint sentences, whichever lands second) holds.

Candidate lesson (reviewer, for the lead to harvest): a note on zz-arch/refusals-are-gate-checks, from c0161 design review 007 F1. A recovery written for a refusal is run end to end, through the same worktrees and commands the skill names, before it is written down. A recovery whose steps each pass alone can still be refused by an older check on the same path (here c0116's `grouped:` record, taken from origin/main). Check: "Has a case walked this recovery, step by step as the skill words it, to the command that refused, and does that command now take it?"

Verdict: changes

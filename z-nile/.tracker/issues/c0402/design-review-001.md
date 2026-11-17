# Review 001: c0402 (design mode)
Inputs: prep worktree `prep-raft-cap-3000-lines` at 45c8cce1d (base origin/main 9885a69c2) with its uncommitted prep: `c0402.md`, `check.sh`, `acceptance/engine.spec.luau`, `skills.spec.luau`, `pins.spec.luau`, `experiments/prototype.patch`, `experiments/mutants.py`; `./zn capture c0402` (956c4d92c); the repo on this base (f0399, R0129, c0286, R0099, f0339, portal R0117, z-ready, z-raft, z-design, zz-rules, zz-test, zz-arch, zz-review); a throwaway clone of the worktree under the session scratchpad (origin removed) for every run below.

What I checked and found sound (no finding):
- Scope fidelity: title, Problem, Non-goals and Solution are word for word the capture's. Each captured outcome has a Design and a Checked criterion (CAP: AC1; the two skill lines: AC2; plan.spec pins 3,000 and passes: AC3). Nothing narrowed. The lesson edit (Guess 1) is required by the chore checklist's Restated rules, and the Guess says so honestly.
- E5 reproduced: on the base, `engine`, `skills` and `pins` fail on assertions only (`expected 3000, got 1500`, `expected true, got false`); the AC4 case passes, as a regression case should.
- With `prototype.patch` applied: `./zn check c0402` passes 4/4; `./zn lessons --check` OK (542 lessons); `./zn promote-check c0402` OK; `stylua --check` and `selene` on `acceptance/` clean; the E3 dry run (the three specs copied to `tests/acceptance/c0402/`, `tests/tooling/repo-fence.spec.luau`) 10 passed.
- E1 reproduced (`./zn run --time 900 -- python3 -I .../mutants.py` in the clone): base green, all 14 mutants killed on an `expected` line, V1 green. My own extras (fill compared against the constant instead of `cap`; the single test hard-coded to `> 1500`; plan.spec's fold case left at its old sizes) each die too: on engine.spec's last case, on its third case, and on AC3's run of plan.spec.
- Override check: the selector over the six Touched paths prints the 11 specs the Design lists. Every promoted spec that reads z-raft or z-design SKILL.md (dispatch-texts, c0117 dispatch and dispatch-cli, c0119 scope-docs, c0120 docs, c0111 skill-docs and lessons-cli, c0047, c0043, c0191, c0115) passes on the prototype (99 passed). The whole c0116 slice plus readycheck and recombine-members ran 64 passed and 3 failed. The 3 (compact-record x2, retired x1) fail the same way with the prototype stashed, so they are not this chore's.
- `raftplan.CAP` has one reader (`raftplan.plan`, called by `main.luau:4386` with no cap argument), so no command but `raft-plan` sees the change.
- `size: 35` is right for the design as written. The prototype is +17/-16 = 33 numstat lines outside the tracker, plus the watch file `finish` writes.
- Repository safety and bounded commands: the new specs only read (`git rev-parse` and `fs.readFile`), `check.sh` runs only specs, and the experiments ran through `./zn run`.

### F1 [high] f0399's sequestered AC7 turns red under a cap of 3,000, whichever item lands first; "nothing fails on the day this lands" is false
Where: c0402.md, Checklist (chore), *Existing work* ("nothing fails on the day this lands"); Design, the search command (`grep -rnE "1,?500" z-nile/engine z-nile/skills z-nile/README.md z-nile/templates z-nile/tests AGENTS.md SETUP.md */skills`); `z-nile/.tracker/issues/f0399/acceptance/plan.spec.luau:73-83`
Evidence: f0399 is prepared, user-approved (approval.md, 2026-11-17) and the only member of the prepared raft R0129. Its sequestered plan.spec (AC7) calls `raftplan.plan` with the default cap. The case "the cap never splits a chore from what it depends on, and still splits what is free" has three chores of 900 (c0011 depends on c0010), with the comment "-- no dependency: 900 + 900 passes the cap of 1,500, so two rafts". I ran it in the scratch clone with f0399's `experiments/prototype.patch` (its raftplan hunk) on top of c0402's prototype: `FAIL ... plan.spec:78: expected deep-equal values`, 5 passed and 1 failed. The free c0012 (900) now fits into the 1,800 dependency bin. Line 82 (`#two == 2`) fails as well, because 900 + 900 is one raft under 3,000. Control, the same tree with `raftplan.CAP = 1500`: 6 passed, 0 failed. Both landing orders break:
- If c0402 lands first, R0129's executor builds f0399 to its design, AC7 goes red, and it cannot edit the sequestered spec, so it must stop.
- If R0129 lands first, `z-nile/tests/acceptance/f0399/plan.spec.luau` is promoted, `--affected` selects it for c0402's change to `raftplan.luau`, and c0402 has no Overrides line for it, so c0402's executor must stop.

The Design's search names no `*/.tracker/**` path, so it could not see this.
Critique: the chore checklist's *Existing work* item asks exactly this, and its lesson's c0302 note says to search `*/.tracker/**/acceptance/` outside `done/` for the old shape. Here the old shape is the default cap that `raftplan.plan(…, {})` calls compute against. The author will be tempted to edit f0399's spec in this prep. That changes f0399's design hash, so its approval no longer holds and R0129's `grouped:` record goes stale (`ready` refuses). It is a re-prep of f0399, not a footnote. The inventory is also wrong in ways the same narrow search explains:
- R0073 is listed as "done" but is in `rafts/active/`; R0071, c0256 and f0399 are backlog items.
- R0110 ("past the plan's about-1,500 cap"), R0128 and c0257 ("over the 1,500-line cap/guide"), and c0121's design-review-003 (`raftplan.CAP = 1500`) are active and not named.
Consequences: either path costs the user something:
- R0129 first: c0402 waits for a 2,300-line raft, gains a `depends_on`, an Overrides entry and a re-cut prototype on f0399's raftplan.
- c0402 first: f0399 goes back through z-design, the user re-approves it, and R0129 is grouped again.

The landing order is the user's call.
Recommendation: escalate to the user: choose the order of c0402 and R0129.
- (a) R0129 first:
  - c0402 gets `depends_on: [f0399]`.
  - Overrides and Touched modules add `z-nile/tests/acceptance/f0399/plan.spec.luau`.
  - The case is rescaled to 1,600 per chore: 1,600 + 1,600 = 3,200 joins only through the dependency; the free 1,600 cannot join a 3,200 bin; the no-dependency pair is two rafts. Its comment says 3,000.
  - `pins.spec` asserts that f0399's promoted spec no longer contains "cap of 1,500" and does contain the new sizes. A Rules row P4 ("f0399's spec keeps 900") is killed by `pins.spec`.
  - The prototype is re-cut on f0399's landed raftplan, and E2 is rerun after it, since f0399's dependency join changes the plan. `size:` grows by about 5.
  - Cost: c0402 waits for R0129. This also closes F3.
- (b) c0402 first:
  - `./zn unfold R0129 f0399`, f0399's case is rescaled the same way in its own re-prep, the user re-approves f0399, and it is folded again.
  - Cost: one re-approval of an approved design, and R0129 waits for it.

Either way, Existing work names f0399 and the chosen path. The Design's search becomes one that can be rerun and covers the tracker, for example `git grep -nE "1,?500|raftplan\.plan\(|raft-plan" -- '*/.tracker/**' ':!**/done/**'`, with each hit judged (it also finds F2's and F3's items), and the inventory's labels are corrected.
Lesson: z-design/new-rules-migrate-existing-work

### F2 [medium] The design says c0286 leaves the cap lines alone, but c0286 edits both of them, and c0286's captured scope (user, 2026-11-16) drops the cap entirely
Where: c0402.md, Order & dependencies ("neither changes the cap lines"; "c0286 … does not read or change `CAP`, so the two merge as separate hunks"); `z-nile/.tracker/issues/c0286/c0286.md:19,36,98`; `c0286/experiments/proto.patch:320-334`; `portal/.tracker/rafts/R0117/R0117.md:26`
Evidence: c0286 (prepared, `design: ready`, no raft) has this in its Problem: "Scope decision (user, 2026-11-16): … this issue also covers f0363 …: raft-plan … **drops the summed-size cap from the plan, z-raft and zz-rules**". Its line 36 quotes the user on 2026-11-15: "Stack them and remove that cap, I've tried to get you to drop it, it was your idea not mine and I don't like it". Portal's R0117 Theme records "the user's standing rule … stack them in one raft, one layer each, with no size cap". c0402's Problem says the user asked on 2026-11-16 for a cap of 3,000, but no user words for 3,000 are quoted anywhere in the repo. On the text, c0286's Design rewrites the same z-raft line 18 ("…never split, unless it is tied (below);") and z-design line 46 ("…never split, unless it is tied."), and its proto.patch carries both hunks with "about 1,500". The design checked only `git diff origin/main...HEAD` in c0286's prep worktree, which cannot see an edit still planned in a document or a patch. At 3,000, two of c0286's ties.spec cases also stop exceeding the cap: c0003 of 2,000 is commented "over the cap alone", and the fold "past the cap" sums to 1,400 + 900 + 100 = 2,400. Its M8 row ("over-cap check runs first") and the fold-past-the-cap rule would then survive, by arithmetic; I did not run c0286's prototype.
Critique: two live user records disagree on whether there is a cap at all, and the design never mentions either. Whichever lands second undoes or reshapes the other: c0286, redesigned to its scope, would delete `CAP` and every restatement c0402 now pins in its own promoted `engine`, `skills` and `pins` specs. The tempting fix is a sentence saying c0286 "will handle it". That leaves the user's contradiction unruled and c0286's sequestered cases hollow.
Consequences: a ruling changes one of the two items' scope, which only the user may do. If the ruling keeps both, c0286's redesign must name c0402's promoted specs and c0116's plan and docs specs on its Overrides line, and c0402 must say that in its Order.
Recommendation: escalate to the user, listing both records with their dates and words. Options:
- (a) 3,000 replaces "drop the cap": c0286's Problem gains a Scope decision narrowing its f0363 part, and c0402's Problem gains a `Decided with the user` line quoting the 3,000 ask.
- (b) 3,000 now and no cap later: c0402's Order says c0286 removes `CAP` and the restatements after it and overrides `tests/acceptance/c0402/*` and `c0116/plan|docs`; the note is sent to c0286's prep and the sending recorded.
- (c) Withdraw c0402 in favour of c0286; the cap stays at 1,500 until c0286 lands.

In every option, correct Order & dependencies to say:
- c0286 edits z-raft:18 and z-design:46, so the two conflict textually and whichever lands second re-cuts them.
- c0402's pins stay compatible with c0286's wording ("…is never split" stays a substring; "cap of about 3,000 lines" survives c0286's ", unless it is tied").
- c0286's 2,000 and "past the cap" cases need sizes over 3,000 in its redesign (sent and recorded).

Lesson: z-design/quote-other-preps-before-promising

### F3 [medium] E2's plan folds f0339 into R0129, so `ready` refuses R0129 until R0099 lands; the design calls E2 harmless
Where: c0402.md, Unknowns E2 ("no refusal, no error, no skip that was not there"; "f0339 folds into R0129"); Checklist *Existing work* ("A person still reads the plan before `--apply`"); `z-nile/.tracker/rafts/R0129/R0129.md` Theme; `z-nile/skills/z-ready/SKILL.md:15`
Evidence: I reproduced E2. `./zn raft-plan` gives 24 commands on the base and 16 with the prototype, including `./zn fold R0129 f0339` in place of `./zn new raft feature ticket-explainer-page f0339`. f0339 has `depends_on: [c0283]`, and c0283 is a member of active R0099. z-ready: "Every `depends_on` of a member issue that isn't a member of this raft names an item in `done/` … If one isn't, stop". So after `--apply`, R0129 cannot be readied until R0099 lands. Today it can be readied at once. R0129 was "grouped alone at the user's request (`/z-raft f399`)" and f0399 was approved on 2026-11-17. The fold also changes R0129's `grouped:` record, making it a raft of two, which needs a coherence review (z-raft §4). R0129's Theme ("Its size is 2,300 lines, over the cap, so `./zn raft-plan` would also make it a raft by itself") becomes false. z-raft §1 calls the no-argument policy "fixed and needs no judgement", and `--apply` runs every line, so a rafter following the skill applies this fold.
Critique: this is existing work that the new figure changes on the day it lands, and the design names the effect without its cost. The tempting answer, "a person reads the plan", contradicts the skill that the person follows.
Consequences: any remedy touches a user-made raft or the order, which is the user's call.
Recommendation: name R0129 in Existing work with the fold, the refusal it brings, the new coherence review and the stale Theme sentence. Then escalate to the user:
- (a) land c0402 after R0129 is readied (F1's option a gives this for free);
- (b) the user marks R0129 `single: true` before c0402 lands, since it was grouped alone at their request;
- (c) accept the fold, and the wait on R0099.

Add a Regression guard line for the chosen path. No spec case is needed for (a) or (b).
Lesson: z-design/new-rules-migrate-existing-work

### F4 [low] A case name and two check labels say something other than what they check
Where: `acceptance/skills.spec.luau:16`; `check.sh` AC1 and AC4
Evidence: the case is named "…and no skill or lesson says the old cap", but it asserts `about 1,500` absent from three files only: z-raft, z-design and the one lesson. AC1 and AC4 each run the whole of `engine.spec.luau`. AC1 therefore also fails when only the solo or explicit-cap rule breaks, and AC4 also fails when only `CAP` is wrong.
Critique: a reader trusts the name and believes every skill is scanned. A later restatement elsewhere would pass.
Consequences: none beyond the Test plan's and the Rules table's case names.
Recommendation: rename the case to "z-raft, z-design and the size lesson say about 3,000, and none of them says about 1,500". Either move the "rules the cap does not touch" case into its own file run by AC4, or say in the AC1 and AC4 labels that each runs all of `engine.spec`.
Lesson: z-design/spec-design-correspondence

### F5 [low] Guess 2 says doubling is the only alternative to an explicit cap; it is not
Where: c0402.md, Order & dependencies, the second `Guess (prep, 2026-11-17)` line
Evidence: "the only alternative is to pass an explicit cap of 1,500, which would stop the spec pinning the default". plan.spec could instead write its sizes from the constant: the over-cap issue `raftplan.CAP + 1800`, the boundary pair `raftplan.CAP - 1000` and `1000` versus `1001`. The new `t.expect(raftplan.CAP).toBe(3000)` line still pins the default. The next change of the figure (F2: c0286 or a later cap) would then touch one plan.spec line, not eight.
Critique: a Guess line is what the user rules on. It should list the real choices and what each costs.
Consequences: none for the build if doubled literals stay. CAP-relative sizes make the case read less like a worked example.
Recommendation: restate Guess 2 with three choices and their costs: (i) doubled literals (chosen); (ii) sizes written from `raftplan.CAP`; (iii) an explicit cap, which stops pinning the default.

Verdict: changes

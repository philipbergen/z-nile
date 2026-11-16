# Review 001: c0278 (design mode)
Inputs: `prep-close-issue-wont-do` at 650d784db0faff820bd9942fdd795edd452411a5. Reviewed: `z-nile/.tracker/issues/c0278/c0278.md`, `check.sh`, `acceptance/{closing,close-cli,readers,docs}.spec.luau` and `experiments/affected.txt`. Also read: `./zn capture c0278` (capture 6ccf1e99a, a confirmed capture with no marker); c0266, c0268 and d0298 on origin/main after `git fetch`; the engine files `main.luau`, `status.luau`, `publish.luau`, `audit.luau`, `board.luau`, `dispatch.luau`, `dispatcher.luau`, `watchcmd.luau`, `raftplan.luau`, `store.luau`, `broker.luau` and `trace.luau`; `z-nile/tests/slow.tsv`, `tests/tooling/watch.spec.luau` and `watch-map.spec.luau`; the zz-rules, zz-test and z-design skills and their lessons.

### F1 [high] The captured outcome "close c0266" is dropped on a guess the document itself says the user has not confirmed, and the step that would restore it has no criterion
Where: c0278.md:20 (the Problem's 2026-11-15 line), Design section 8 (c0278.md:163), Acceptance criteria.
Evidence: The capture ends "then close c0266 and c0268 with it". The only record for dropping c0266 is a line headed `Scope decision (user, 2026-11-15)`. Its text says "GUESS made by Claude, NOT YET CONFIRMED by the user … The user confirms or overrules this when approving." Section 8 adds "If the user overrules the guess, closing c0266 comes back as its own criterion and step". That step waits on a person and has no AC, spec case or Rules row, yet the document is marked `design: reviewed`. `./zn trace` makes each Problem paragraph a claim (trace.luau:23). The final review therefore needs c0278:P1 met, or `not met: "<ruling>"` quoting a human ruling from `## Open to the human`, and there is no ruling to quote.
Critique: Rule 11 (scope fidelity) needs the user's decision for a dropped outcome. A line labeled `(user, …)` whose own words say it is not the user's does not count as one. Every later reader will still take it for a ruling: z-raft's Theme, `./zn capture`'s "plus the `Scope decision` lines added since", and the final review. The tempting fix is to keep the line and rely on `./zn approve`. But approve records a hash of the text, not a ruling on this outcome. And if the user overrules at approval, there is no criterion for the executor to deliver.
Consequences: Moving the question under `## Open to the human` makes `status c0278 prepared` and `ready` refuse until the user rules (z-design step 4), which is the gate this decision needs. The ruling is then quotable by the final review. Option B also reaches other items. d0298 (R0096, prepared) names c0266 in `depends_on` on origin/main, so `close` would refuse c0266 (refusal rule 8) until a PR drops that dependency. And c0266 is `prepared`, with a design built on the user's own 2026-11-12 scope.
Recommendation: escalate to the user, with these options:
- (A) Close only c0268, the guess. It agrees with c0266's own `Scope decision (user, 2026-11-12)`, which gave c0266 a new scope ("Rewrite the spec that forbids features and defects in z-nile's root so all three types are allowed there"), so c0266 is no longer moot. Cost: recording the ruling only.
- (B) Close c0266 too. Cost: a PR dropping c0266 from d0298's `depends_on`, which changes d0298's design and re-reviews R0096's rafting. It throws away c0266's merged design (#394) and the user's 2026-11-12 scope. It also needs an AC, a check line and an Implementation step for the c0266 close in c0278.

Record it as `- F1: …` under `## Open to the human`. Once ruled, replace the guess line with the user's words as a real `Scope decision (user, <date>)` line. Then either delete section 8's conditional sentence (A), or turn it into that AC and step (B).
Lesson: z-design/never-narrow-captured-scope, z-design/no-open-question-in-a-reviewed-design

### F2 [high] AC8's watch-net half passes with watch-net unchanged: only the new pure helper is tested, and the named guard never runs watch-net
Where: Design section 4, watch-net bullet; readers.spec :: "watch-net's open-defect test ignores a closed defect and keeps done/ and retired/ closed"; Regression guard (c0278.md:258); AC8.
Evidence: The case only calls `watchcmd.isOpenDefect(path, text)`. Consider this mutant: export a correct `isOpenDefect`, and leave `openDefect` (watchcmd.luau:664-675, called at :841) testing paths only, as today. readers.spec stays green and AC8 passes. Then, once a `slow-tier-red` defect is closed as won't do, watch-net prints "the slow tier failed; defect slow-tier-red is already open" for every later red slow tier and never files a new one.

The Regression guard names `tests/tooling/watch.spec.luau` as watch-net's guard. That spec tests `z-nile/lib/watch` (the watch map) and never runs watchcmd. The spec that drives `openDefect` is `tests/tooling/watch-map.spec.luau` (case "a green fast suite runs the slow tier, and a slow failure opens one defect"). It is in `slow.tsv` (38.6 s), so neither check.sh nor any gate runs it.
Critique: The criterion is about watch-net's behaviour, but the case pins a helper that its real caller may never call.
Consequences: An end-to-end case needs watch-net's preconditions in a fixture, as watch-map builds them: a stub `z-nile/check.sh` that fails on `--slow`, a `z-nile/watch-passed` marker, and a source commit after the marker. `openDefect` greps `dir`'s working tree (no revision), so the closed defect has to be in that tree, not only on origin.
Recommendation: Add a readers.spec case modelled on watch-map's. Seed `z-nile/.tracker/issues/d05xx/d05xx.md` with `slug: slow-tier-red`, a `closed-…` status and a `wont_do:` line. Run `./zn watch-net` and assert both "pushed a defect" and two `slug: slow-tier-red` documents on origin/main. As a control, the same run with an open defect prints "already open". Add the Rules row (mutant: `openDefect` does not call `isOpenDefect`). Correct the Regression guard to name watch-map.spec, and put that spec in the one-time slow run of F3.
Lesson: zz-test/pin-fail-safes-where-they-act

### F3 [medium] The regression guard relies on slow-tier specs that it says "the full gate at the merge" runs; no gate runs them, so the guards of the new status, idea and watch-net refusals never run
Where: AC12 (c0278.md:363), E6, Regression guard (c0278.md:254), Implementation step 5.
Evidence: AC12 says `c0116/claims` "is a slow-tier spec that d0298 names, and the full gate at the merge runs it". The zz-test skill says otherwise (SKILL.md:12-13): `--full` is "every spec outside the measured slow tier", and `--slow` is "not part of the affected or full gates".

The Regression guard's specs for the order of the new refusals include `c0116/claims` (slow tier, 450.9 s) and `tooling/idea` (slow tier, 20.0 s). Neither is in check.sh. Other slow-tier specs drive commands this chore changes:
- `c0116/retired`, 497.0 s: the `status`, `new raft` and `fold` refusals. It is listed in Affected specs.
- `c0053/commands-claim`, 15.0 s: status claims.
- `tooling/watch-map`, 38.6 s: watch-net (F2).
- `c0117/dispatch-cli`, 406.1 s: the dispatcher. Its family is listed in Affected specs.

Meanwhile AC12 runs four slow-tier specs at every `finish`, `restack` and `done`, with no seconds or reason given: `c0053/publish` (13.2 s), `c0067/publish-move` (10.9 s), `tooling/board` (8.0 s) and `c0082/cli` (5.6 s). The search behind these figures: the AC12 list, the Affected specs and the spec paths in `z-nile/tests/slow.tsv`, grepped for `"status"`, `"idea"`, `"audit"`, `"list"` and `dispatch.next`.
Critique: The closed refusal inserted into `setStatus`'s target loop is exactly what `c0116/claims` pins. After prep, nothing checks it until watch-net's slow run after the merge, on main.
Consequences: Putting about 1,400 s of slow-tier specs in check.sh would cost that time at every `finish`, `restack` and `done` (lesson zz-test/check-sh-never-runs-the-slow-tier). Also, `c0116/claims` already has one red case on the unchanged tree (`claims.spec:534`, E6), so "still passes" has to mean "the same reds as origin/main".
Recommendation:
1. Correct the sentence in AC12 and E6.
2. Add an Implementation step after step 10 that runs `z-nile/check.sh --slow -- tests/acceptance/c0116/claims.spec.luau tests/acceptance/c0116/retired.spec.luau tests/acceptance/c0053/commands-claim.spec.luau tests/tooling/idea.spec.luau tests/tooling/watch-map.spec.luau tests/acceptance/c0117/dispatch-cli.spec.luau` once on the finished layer and once on origin/main. The Verification log records that the reds are the same.
3. For AC12's four slow-tier specs, either state the measured seconds beside the line and why they stay (they pin the publish guard, `list` and the board, which this chore changes), as that lesson's c0302 note asks, or move them into the one-time run.

Lesson: z-design/guards-name-slow-tier-specs, zz-test/check-sh-never-runs-the-slow-tier

### F4 [medium] `./zn land` is a second direct-push path that the closed rules don't cover: a capture can edit a closed document, and can add a `depends_on` naming a closed issue
Where: Solution (c0278.md:36), Design sections 5 and 7 (the direct-push bullet), Non-goals (c0278.md:26), main.luau:2313-2385 (`captureScope`).
Evidence: `land` pushes one commit straight to main after `captureScope`. `captureScope` accepts an edit (M) of `<root>/issues/<ID>/<ID>.md` when the document is `design: draft` on both sides, its status line is unchanged, and only `title`, `depends_on` (CAPTURE_KEYS) and the sections differ. A closed c0268 stays `design: draft`, so two kinds of capture land:
- (a) a capture that rewrites c0268's Problem;
- (b) a capture that adds `c0268` to another draft issue's `depends_on`.

Neither goes through publish.commit's existing-document test, and neither meets the dispatcher's merge-gate audit (dispatcher.luau:1606-1615 audits PR merges only). A dispatched land goes through the broker, which checks only trackerstate's paths (broker.luau:127).

The design's own text says otherwise. The Solution says the guard "refuses any later publish of a closed document". The zz-rules edit writes "never again once closed" into the very bullet that also describes land's pushes. The Non-goal says "This chore stops one from being created (`close` refuses, `audit` reports)".
Critique: (b) is the harmful case. The dependent can never be readied, because a closed issue is never `done`, and the only report is `./zn audit`, which no gate runs. The tempting fix is to reword the claims, which leaves the hole open.
Consequences: `land` must read the document of each id that a capture newly adds to a `depends_on`, at `base`: one lookup and one `git show` per added id, and only when `depends_on` changed. A dependency on a closed issue that is already on `base` (from a hand-merged PR) is not the capture's to fix, so only ids the capture adds are refused.
Recommendation:
1. In `captureScope`, refuse an edited document whose `base` version is `closing.closedDoc`: `not a capture change: <path> is closed (won't do): its document is never published again`.
2. Also refuse a `depends_on` that adds an id closed at `base`: `… <id> is closed (won't do): drop it from depends_on`.
3. Add close-cli cases in a `capture-<slug>` worktree with `PICKMAN_LAND_GATE=true`, as `c0072/land` does: an edit of closed c0510's Problem is refused with origin's tip unchanged; adding c0510 to c0550's `depends_on` is refused; adding a live id still lands.
4. Add the Rules rows, and name the refusal in zz-rules' `land` sentence.
5. Reword the Non-goal to name what stops a new dependency (`close`, `land`, the dispatcher's merge audit) and what is left (a hand-merged PR, which only `audit` reports).

Lesson: zz-arch/one-definition-of-tracker-state

### F5 [medium] AC11 cannot tell the carried close from a published one, and does not see a dependency added on main after the carry
Where: check.sh `closed_here` (AC11), the last row of Rules and mutants, Design section 8, Implementation step 11.
Evidence: The last Rules row says AC11 kills "the executor publishes the close instead of carrying it (the branch's c0268 stays `new`)". But after any `./zn sync` (and after a restack onto origin/main) the branch holds origin/main's c0268, so it is `closed-…` with its `wont_do:` either way, and AC11 passes for the mutant. Yet this mutant is exactly what section 8 exists to prevent. Main would hold a `closed-…` stamp that its own engine reads as `new` (`status.parse` returns nil without `closed` in `NAMES`, and `derive` gives `new`), and that engine's publish guard accepts a status-only claim of it.

Separately, `closed_here` reads only this tree. A `depends_on: [c0268]` landed on main after the carry (F4's path) therefore merges silently into a `closed-dependency`.
Critique: A Rules row whose case can't fail (review item 0), and a carried judgment that nothing re-judges when the branch lands.
Consequences: check.sh is rerun from `done/` after the merge, so the check must stay true then. It can't require c0268 to be `new` on origin/main.
Recommendation:
- In `closed_here`, also fail when `git log --format=%s -- <c0268's document>` on HEAD contains `tracker: close c0268 won't do`. A published close leaves that subject in history for good, while the carried close is the layer's own commit.
- Also fail when `git grep -w -e c0268 --and -e '^depends_on:' origin/main -- <roots>` names a document outside `done/`. `done` fetches before it runs the raft's check.sh, so this sees the current main.
- Make step 11 say to commit the edit (`./zn commit`), as section 8 says.
- Update the Rules row.

### F6 [medium] Several cases the Design enumerates are never seeded, so their mutants survive
Where: readers.spec (the audit case and the publish-guard case), close-cli's refusal cases, Rules and mutants.
Evidence: These branches are stated in the Design, but no case seeds them:
- audit `closed-not-backlog` for a closed issue in `active/`, and for a raft document that is closed or carries `wont_do:` (only `done/c0630` is seeded);
- `closed-in-raft` from the raft's side: a raft whose `issues:` names a closed issue whose own `raft:` is empty;
- `closed-dependency` from an `active/` dependent;
- `closed-mismatch` for a closed status with an empty `wont_do:`;
- `close`'s dependents rule for an active dependent (holds the issue), a closed dependent (does not) and a hit that is not an item document (a `design-review-001.md` line starting `depends_on: [c0590]`, which the item-document filter must drop);
- the `closing.closedDoc` refusal in `validateMoves` (section 5), which has neither a case nor a row.

Mutants that pass today: audit tests only `/done/`; audit skips rafts; dependents are counted from backlog items only, or from closed items too, or from any grep hit. Also, `refused(R, {"fold", "R0510", "c0520"}, "c0520")` accepts any refusal whose text names c0520.
Recommendation:
- Seed each case above in the existing fixtures (one extra file each, no new fixture) and assert each code's message.
- Add a publish.commit case that moves closed c0510's folder to `active/` and is refused with "never published again".
- Tighten the `fold` needle to `c0520 is closed`.
- Add one Rules row per branch.

Lesson: zz-test/seed-every-enumerated-case

### F7 [low] Executability slips
Where: c0278.md:105, :240, :374; publish.luau:130.
Evidence:
- (a) Section 2 calls `stamp("closed")` "the existing fresh-stamp helper that `status` uses (redrawn until new on `origin/main` when publishing…)". But `stamp` (main.luau:384) is a plain draw, and that is what `setStatus` uses (main.luau:1524). The redraw-until-new helper is `freshStamp` (main.luau:638).
- (b) E4 can be answered now, and the design's primary form fails it. On this checkout, `git grep -n -E '^depends_on:.*\b(c0266|c0268)\b' origin/main -- z-nile/.tracker pickman/.tracker arcade/.tracker` prints nothing, while `git grep -n -w -e c0266 --and -e '^depends_on:' origin/main` finds d0298 (and nothing for c0268).
- (c) Step 3 names `c0067/publish`, which does not exist; `c0053/publish` is meant.
- (d) The comment at publish.luau:130 ("A published edit of an existing document may differ from origin's only in that line") restates the rule this chore changes, and section 7 doesn't list it.

Recommendation: Name the helper meant (either one works, since a closed stamp needs no claim freshness). Make the `-w --and` form the design and record E4's result. Fix the spec name in step 3. Add the publish.luau comment to section 7.

### F8 [low] E3's probe loop is not recorded as bounded
Where: Unknowns, E3.
Evidence: "`git show origin/main:<doc>` ×50 took 1.63 s" is a loop the author started that is not the gate, a check or a `./zn` command. The record does not say it ran under `./zn run --time`.
Recommendation: State the `./zn run --time <s> -- …` command E3 used, or rerun it that way.

## Lesson candidates (for the lead)
- z-design/never-narrow-captured-scope, sharpen its check: "Is each `Scope decision (user, …)` line the user's own words, and not a guess recorded under their name?" Why: F1. A guess written in the user-decision form passes rule 11's line test while saying it is unconfirmed.

Verdict: changes

# Review 007: R0026 (design mode)
Inputs: prep worktree `prep-guard-follow-ups` at 9cf83bd (`git diff HEAD~1 -- tracker/`): c0083 (`c0083.md`, `check.sh`, `acceptance/suites.spec.luau`), `R0026.md` and `check.sh`, c0074 and c0080 where they name the gate, `tracker/issues/c0072/c0072.md`; design-review-005/006 and design-refute-005/006; the review, testing, tracker, ticket-prep and execute-raft skills; `.github/workflows/check.yml`; `scripts/tracker/main.luau` (`new raft`). Prototype `.worktree/proto-r0260`, read only: `scripts/lib/suites.luau` (`sideOf`), `scripts/lib/changed.luau`, the `stop.sh` diff; `lune run scripts/affected -- --which <path>` for the paths in F6, and `-- tests/unit/gone.spec.luau`. One scratch git repo under `$TMPDIR` (removed) for F2's mutant.
Dropped from design-review-006: F4 (the hook's `--no-renames` holds: the old path reaches the selector, and the gate then reselects through `changed.files`, which already lists both paths and never selects a deleted spec), F7 (except the weak count in F7 below). F1, F2, F3, F5 and F6 are fixed in part. What their fixes break or leave open is F1–F6 below. The user's four decisions aren't re-opened.

### F1 [high] The permanent "no raft outside done/ runs check.sh --full" case turns `main` red after any ungated `tracker.sh new raft` from an older worktree, and nobody is then allowed to fix it
Where: `suites.spec.luau` case "no raft outside done/ runs check.sh --full as its gate"; c0083 "Template drift"; design-refute-006 F5; `scripts/tracker/main.luau` `new raft` (lines ~493–500); tracker skill, "The direct-push exception"; `check.yml` (`paths-ignore: ['tracker/**']` on push).
Evidence:
- `new raft` renders `tracker/templates/raft/check.sh` from the **local worktree** and publishes the new raft's `check.sh` to `origin/main` as a direct push. Commit 515bd7e (`tracker: new raft R0027`) shows this: `tracker/rafts/R0027/check.sh | 16 +` straight to main. No gate runs, and CI ignores `tracker/**` on push.
- So a prep worktree created before c0083 lands (R0011 and R0012 are `preparing` in other sessions right now) that runs `new raft` afterwards puts a `--full` RC0 on `main` without anyone seeing it. From then on, the promoted c0083 case fails on `main`:
  - Every harness raft's Phase 0 baseline (`check.sh --suite harness`, which includes this harness spec) is red: "If main is red, stop".
  - Every PR's CI (`setup.sh` runs `--full`) is red, game PRs included. A game PR's `--affected` never selects the case, so the executor reads it as a selector miss. Merging 3's new guard forbids touching a sequestered file, and the only fix is another raft's sequestered `check.sh`. So every executor ends at `BLOCKED:`.
  - The red lasts until that prep lands its PR. This raft's own prep has run seven rounds.
- review-006 F5 asked for this check "without a spec that reads tracker state and can turn red on someone else's direct push". The fix chose exactly that kind of spec.
Critique: the tempting fix is to give the case an exception (skip rafts whose `design:` is `draft`, or rafts younger than the template change). That's still a spec over live tracker state. It goes red as soon as such a raft reaches `reviewed`, which is a prep commit, and it still blocks unrelated work.
Consequences: drift has to be caught where it's born, in the prep of the raft that carries it. That prep's own design review and landing gate see it. Then a stale RC0 costs one raft one both-suites run, a breach of "Nowhere" for one raft only, not an outage. A design reviewer can miss it. If that's not acceptable, the source can be removed instead: `new raft` could render the template from `origin/main` (`git show origin/main:tracker/templates/raft/check.sh`). That's a change to `scripts/tracker/main.luau`, outside c0083's Touched modules, so it needs a case and a Touched line.
Recommendation:
- Drop the permanent spec case and its Rules row. Keep the one-time AC9 grep in c0083's `check.sh`, which runs only for this raft.
- Add the line review-006 F5 proposed to the review skill's design-mode item 2 ("RC0 runs `scripts/check.sh --affected`; a raft `check.sh` with `--full` is a finding") and to ticket-prep's exit-criteria step. AC8 greps both.
- Optionally, `new raft` renders from `origin/main`, with a `tracker` case: a stale local template doesn't reach the published `check.sh`.

### F2 [high] AC9's "exactly the RC0 line" check passes an edit that deletes another raft's gate
Where: c0083 `check.sh` AC9 (the `removed`/`added` loop and the spec-case grep); R0026 "Binding exception" ("which c0083's AC9 proves are each the RC0 line alone").
Evidence: in a scratch repo, I replaced R0011's `check "RC0: repo gate passes (full)" scripts/check.sh --full` with `# RC0 moved to scripts/check.sh --affected (c0083)` and also deleted a blank line. AC9's loop printed no failure:
- the removed line has `--full`, and the added comment has `--affected`;
- `^-[^-]` and `^\+[^+]` don't count a removed or added blank line.

The new spec case passes too, since the file no longer names `--full`. So that raft loses RC0 entirely, and the code reviewer is told by the Binding exception that AC9 proved the diff is "the RC0 line alone". Also:
- the pathspec `tracker/rafts/*/check.sh` matches `done/R…` too, so an edit to a finished raft's file passes;
- the spec-case check only looks for a `FAIL` line, so a deleted case or a spec that doesn't load passes it.
Critique: the tempting fix is `grep -q '^+check "RC0'`. That still lets the label or extra arguments drift (`--affected --suite game`).
Consequences: the added line has to equal a known string. The template's new RC0 line is the natural reference. Since the template is also changed in this raft, compare against the branch's `tracker/templates/raft/check.sh`, which AC8 already checks.
Recommendation:
- For each changed file outside `done/` and `R0026`, compare `git diff -U0 --no-color` hunks in full, blank lines included. Exactly one `-` line, equal (`-xF`) to `check "RC0: repo gate passes (full)" scripts/check.sh --full`, and exactly one `+` line, equal to the template's RC0 line.
- Any changed `check.sh` under `done/` fails AC9.
- If F1's case stays, it's checked with `cases_in`.
- Record the mutant "RC0 replaced by a comment" in E4 as `run`.

### F3 [high] AC8's rewritten checks pass today's unchanged commands-table line, and a Merging section that still sends a selector miss to `BLOCKED:` (partial repeat of review-006 F2)
Where: c0083 `check.sh` AC8 (`grep -qiE "on demand|CI"`, `grep -i "graph miss"`, the Merging `selector miss` grep); Rules rows "no step runs `--full` as the gate" and "a selector miss is fixed forward … or Merging still saying `BLOCKED:`".
Evidence:
- AC8's per-line test run on today's testing skill: line 12, `| \`scripts/check.sh --full\` | every spec. Used by raft \`check.sh\` files and by CI |`, **passes**, because it says "CI". So the commands table can keep calling `--full` the raft gate. `-i` also makes "CI" match "spe**ci**fied", "de**ci**de" and "suffi**ci**ent": `RC0 runs scripts/check.sh --full, as specified` passes. review-006 F2 named that exact hazard.
- The Merging check needs only the words "selector miss". "A selector miss is red like any other: post `BLOCKED:` and stop" passes it, which is the Rules row's own mutant. None of the guards (the spec run by name, the review round, the forbidden files) is checked.
- The Graph-miss check reads only the line holding "Graph miss". The design writes the rule as four bullets. If the executor keeps a `**Graph miss**:` lead line with the bullets under it, "selector miss" sits on the next line and AC8 fails a correct rewrite.
Critique: the tempting fix is `grep -w CI`, which line 12 still passes.
Consequences: each check needs a phrase only the new text has, plus the absence of the old one, and it should read a section, not one line.
Recommendation:
- Testing skill: fail if any line naming `--full` also matches `raft|RC0|exit criteria` (case-insensitive), and require `on demand` (case-sensitive `CI` allowed) on the rest.
- Graph miss: read the paragraph from "Graph miss" to the next bullet at the same level (`sed`/`awk`). Require "selector miss", "PR's branch" and `tracker.sh new issue c`.
- Merging: require "selector miss" together with `lune run tests/run --` and "review" in the same bullet or paragraph, and fail if that paragraph says `BLOCKED:` other than for the guards.
- Run the three mutants (line 12 unchanged, Merging saying `BLOCKED:`, the bullet layout) and record them as `run`.

### F4 [medium] The selector-miss path in Merging 3 leaves the executor to guess what counts as a miss, which review round it writes, and what happens when that round finds something
Where: c0083 "The tracker skill's Merging 3 carries the same rule" (four bullets); table rows for Merging 3 and 4; execute-raft Phase 4 step 7 (cap of 3 rounds); review skill, code mode, Inputs (`git diff origin/main...HEAD`); `tracker.sh commit` ("needs an active raft").
Evidence:
- **What counts as a miss**: the bullets define a miss as "a spec … no local gate selected" but give no test for it. Red CI also comes from a selected spec that passes on macOS and fails on Linux (unjailed, a different platform), or from a spec already red on `main`. Neither is a selector miss. The only discriminator, `lune run scripts/affected` on the branch, doesn't contain the spec, and the design never asks for it. review-006 F3(a) did.
- **Which round**: "a code review round of its own" is a code-mode `review-NNN.md`:
  - The raft is in `done/` by then, so the file lands in `tracker/rafts/done/<R>/`, and `metrics` counts it as a rework round.
  - If the raft already used three rounds, it's `review-004.md`, and Phase 4 step 7 has no rule for a round after 003.
  - Nothing says what happens when it finds a high: `done` has already run and never re-reads the refute file.
  - Code mode's Inputs are the whole branch diff, not the fix's.
- **Failure**: "touches no promoted spec … and no sequestered file" gives no outcome when the fix needs one.
- **Commit**: a commit after `done` has to use plain git (`tracker.sh commit` needs an active raft), and its spend is lost. The design doesn't say either.
Critique: the tempting fix is a sentence per gap in Merging 3. That's right, but each sentence needs a definite outcome, or the executor improvises after `done`, which is the R0021 incident.
Consequences: this review round is outside the numbered rounds, so its own name has to keep it out of `done`'s and `metrics`' counting. A high there must stop the merge, because no later round exists.
Recommendation: Merging 3's path, in order:
- (a) run `lune run scripts/affected` on the branch. Only a failing spec absent from its output is a miss. A selected spec failing, or a spec that also fails on `origin/main`, is `BLOCKED:`.
- (b) if the fix would touch a promoted spec or a sequestered file, `BLOCKED:`.
- (c) run the spec by name and `check.sh --affected`.
- (d) commit with plain `git commit`, noting `--time` in the PR comment.
- (e) a clean Opus reviewer in code mode on `git diff <done sha>..HEAD` only writes `review-fix-NNN.md` (ignored by `done` and `metrics`), and any high finding in it means `BLOCKED:`.
- (f) file the selector chore, then Merging 2–4.

AC8 (F3) checks (a), (b) and (e).

### F5 [medium] c0072's capture gate keeps `--full` whenever R0025 executes first, and its "after a local full gate" clause is neither changed nor checked
Where: c0083 "R0025's c0072 … Design (step 4) and Problem"; AC9's c0072 grep (`scripts/check.sh --full` only); `c0072.md` lines 19, 49 and 63; R0025 `design: ready`, status `prepared-…`; R0025.md ("R0021 must be in `done/` before `start`"); `tracker/rafts/done/R0021` exists.
Evidence:
- R0025's only blocker, R0021, is done, so R0025 can start today. Nothing orders R0026 before it: R0026 says "No member depends on an item outside the raft", and c0072 has no `depends_on` on c0083.
- If R0025 lands first, `tracker.sh land` ships running `scripts/check.sh --full`, and the tracker skill's direct-push clause ships saying "after a local full gate" (c0072 line 63). c0083's step 5 then edits `tracker/issues/done/c0072/c0072.md`, a finished document, which changes no behaviour. AC9's `tracker.sh find c0072` returns the done copy and still finds `--full` there, so it demands that pointless edit. The `land` code stays on `--full`, outside every Touched module and check. That's a gate running both suites for a change that touches neither, the opposite of "Nowhere".
- If R0026 lands first, line 63's "after a local full gate" isn't in the edit list, and AC9's grep can't see it. R0025's executor then writes "full gate" into the tracker skill. AC8 only greps `check.sh --full`, so that wording stays.
Critique: the tempting fix is to add `depends_on: [c0083]` to c0072. That holds R0025 behind this raft, which is a scheduling decision for the user, not the author.
Consequences: without an ordering, c0083 has to handle both orders, and the done order touches code in another raft's finished work. That's still within "Change them in this raft", but it adds a Touched module and a case.
Recommendation: c0083 step 5 branches on c0072's state at execution.
- **Not done**: edit lines 19, 49 and 63 ("after a local gate (`scripts/check.sh --affected`)").
- **Done**: change `land`'s gate command in its implementation (named in Touched modules as conditional) and the tracker skill's direct-push clause. Pin it with a case driving `land` with `PICKMAN_LAND_GATE` unset in a stubbed fixture, or a grep of the implementation.

Then:
- AC9 greps c0072.md for `check.sh --full|full gate` (case-insensitive) only when it isn't done, and the land implementation for `--full` when it is.
- AC8 also fails on "full gate" (case-insensitive) in the tracker skill.
- If the user prefers ordering, ask them for the `depends_on` instead.

### F6 [medium] `--which` classifies paths differently from `suites.of` and `select`: a game chore spec gets a harness baseline, and every unlisted path adds the harness suite
Where: c0083 `--which` (`suites.sideOf`: "… else `harness`"); the Phase 0 row; prototype `scripts/lib/suites.luau` lines 84–101; the issue template's Touched-modules comment ("INCLUDING this issue's spec paths").
Evidence (prototype):
- `--which tests/acceptance/c0041/place-game.spec.luau` prints `harness`, but `suites.of` says `game` (the spec's own case 1 pins it). A chore raft fixing that spec baselines the harness suite only and never runs the spec it touches, so a red-on-main spec shows up mid-raft. That's review-005 F3's problem again.
- `--which tracker/game-design.md` prints `harness`, and so does `tracker/issues/f0054/acceptance/docs.spec.luau` (a feature's unpromoted spec). `select` gives neither path the harness suite: the first selects only its text readers (f0054's game spec), the second is a game spec by rule 4 once promoted. So a feature raft listing its acceptance folder, or any doc, baselines both suites. That's the 48 s harness suite the user asked game work not to pay ("Nowhere").
- `--which` with no paths prints both. That's the safe direction, but undocumented.
Critique: the tempting fix is to add `tracker/issues/[fd]` to the game patterns. That still leaves chore specs and docs wrong, because `sideOf` is a second classifier beside `of`.
Consequences: `--which` should agree with the selector's own rules:
- a spec path takes `suites.of` (this needs the graph, which `affected` already builds);
- an unpromoted acceptance spec takes the rule it will have once promoted;
- a path that no pattern claims takes the sides of its `--deps` specs, or nothing.

An empty answer then needs a rule (static stages only: `check.sh --affected`).
Recommendation: implement `sideOf(g, path)` as above, and say in Phase 0 what an empty `--which` means. Add cases to the selector's command-line test:
- `--which tests/acceptance/c0041/place-game.spec.luau` gives `game`;
- `--which tracker/game-design.md` gives `game` (its reader is f0054's spec);
- a synthetic `tracker/issues/f…/acceptance/x.spec.luau` gives `game`.

Run the mutant "`sideOf` without the spec rule" and record it.

### F7 [low] AC7's `-ge 2` count passes with the Affected-specs step unchanged
Where: c0083 `check.sh` AC7 (`grep -cF -- "scripts/affected -- --deps" … -ge 2`); ticket-prep line 31.
Evidence: the Override check is one line, and the design rewrites its `ALL` sentence to talk about `--deps`. If that sentence reads `scripts/affected -- --deps` twice, the count reaches 2 while line 31 still says "run `lune run scripts/affected -- <paths>` and paste its output".
Recommendation: fail AC7 if ticket-prep still contains `scripts/affected -- <paths>\` and paste`, instead of counting.

Verdict: changes

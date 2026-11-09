# Review 002: c0276 (design mode)
Inputs: prep worktree `.worktree/prep-board-shows-lost-work` at 5d8fb89f with the working-tree c0276.md (sha256 70b9156b70c9…), check.sh (84e40af12870…), acceptance/board.spec.luau (e9ba320f29ab…), acceptance/verdicts.spec.luau (e613c653edc1…), design-review-001.md, design-refute-001.md (5ee63be7e018…), harvest.md and the two lessons it adds; prototype origin/proto-c0276 4323b6a3 (its check.sh and both specs are byte-identical to the prep's); `git diff origin/proto-c0265-raft origin/proto-c0276 -- z-nile/engine z-nile/README.md z-nile/skills`; c0265's document (origin/prep-work-heartbeat); the c0274, c0275 and c0277 hand-offs and c0274's prep (`.worktree/prep-take-over-lost-claim`, which lists the board under Non-goals as c0276's); c0121, c0180 and c0284 documents; `./zn capture c0276` (8577a496, a confirmed capture: title, Problem and Non-goals unchanged, Solution only gained detail). Main moved 50 commits past the prototype's base 1758cf21; of the files the specs load only `tests/lib/fakecli.luau` changed (the model-CLI fake's `FAKE_DELAY` and pid files), which the two specs don't use. All runs were in scratch clones of proto-c0276 with origin removed (`scratchpad/rv2`, `scratchpad/rv3`); mutation scripts `scratchpad/mut2.py`, `scratchpad/mut3.py`. Nothing in the repository was edited.
Dropped from review-001: F2, F3, F5, F6. Re-run on the prototype, one mutant at a time: Ma (verdicts 4p/2f), Mb (4p/2f), Mb2 the Done bucket alone (5p/1f), Mc (5p/1f), Md (5p/1f), Mf (board 10p/1f at board.spec:267), Mg (10p/1f at :278), Mi (10p/1f at :290), Mj (10p/1f at :249), Mh (10p/1f at :311), M10 (10p/1f at :323), M16 (10p/1f at :327), M12 (10p/1f), plus my own N1 `cmd.board` passes `fresh=true` (10p/1f), N2 lost drawn without minutes (5p/1f), N3 lost sorted by ascending silence (5p/1f and 10p/1f), N7 card without the mark (5p/1f), N8 rafts never marked (4p/2f), N13 the guard asked loudly (10p/1f), N17 stale drawn as lost (5p/1f). AC4's greps pass on the prototype, and the board row of `proto-c0265-raft` holds none of its words (`grep -F "| board |" | grep -cF parked` → 0). The second worktree is `c0276-pub`, and c0275's exemption is quoted as its hand-off states it. F1 and F4 of review 001 are repeated in part below (F2, F4).

### F1 [high] A raft's own claim never shows on the Board view, and AC2 passes when the engine drops every raft verdict
Where: Design §2 (`mark()` "after the type on a board card, after the stage badge on a list row, and in the heading of the issue and raft panes"); §1 Order ("The bands themselves keep their order"); Usability ("a lost raft's members show it too"); board.spec's setup (lines 120-152); Rules and mutants; AC2 ("carry each verdict").
Evidence:
- `claimsOf` makes one claim per document, with the document's own id (`id = fid`; a raft's members go into `match`, which only parking reads), and `heartbeat.judge` gives each verdict `id = c.id`. A raft claimed by z-raft (`new raft` over prepared issues, `fold`, `recombine`, `status <R-id> preparing`) "stamps the raft only" (zz-rules, Rafting), so its members carry no stamp and get no verdict. Only `ready` stamps the members (zz-rules: `stop` gives back "exactly the issues that carry the raft's stamp").
- The Board view, which the page opens on, draws cards for issues only and draws a raft as the band head `idLink(b.raft)`, with no mark (board.html, `renderBoard`). I ran a probe of verdicts.spec's page case with one verdict, `R0010` lost: the band head is `<div class="raft"><a class="jump" data-id="R0010" href="#R0010">R0010</a> title R0010 <span class="badge s-preparing">preparing</span></div>`, and `out.board` holds no `class="mark` at all. The Rafts list does show `m-lost`. So a lost rafting claim (a z-raft session that died) is invisible on the default view, and Usability's "a lost raft's members show it too" holds only for a readied raft.
- board.spec seeds issue claims only (c0010 to c0090). Mutant N9, `boardVerdicts` keeps only the verdicts whose id does not start with `R` (`if string.sub(v.id, 1, 1) ~= "R" then table.insert(marks, …) end`): board.spec 11 passed, 0 failed. verdicts.spec is pure and never sees the engine edge, so AC2 ("carry each verdict") passes with every raft verdict dropped.
- Bands keep their order (raft id order, the loose band last: `boardview.bands`). A lost readied raft's band, all of its cards marked lost, stays behind other rafts' live bands in the ready and run columns, so on the default view lost work is first only inside a band.
Critique: The capture's first outcome is that the board shows each claim's verdict. Rafts are half of the claim kinds, and the round-1 fix seeded them only in the pure spec. The tempting fix is to seed a raft in board.spec and stop there. That kills N9 but leaves the default view blind to a rafting claim.
Consequences:
- A mark in the band head is drawn only when the raft has `heartbeat`. Without verdicts `mark()` returns "", so c0118's page strings don't change.
- A raft claim seeded in board.spec must hold under the later layers, as the issue claims do: a seeded `preparing-…` stamp (or one made at the case), its beat force-pushed by `other` after the last command of any worktree holding it, and no command run in that worktree afterwards.
- The raft lands in `views.rafts["not"]`, so the existing `position` assertions on `views.issues["not"]` are unaffected.
- Moving a lost raft's band forward is a new ordering rule, with its own tie rule (longest silent first; the rest in raft id order; the loose band last).
Recommendation:
- board.html: draw the raft's mark in the band head (`idLink(b.raft) + mark(byId[b.raft])`). In verdicts.spec's page case, assert a lost raft's mark inside its `<div class="raft">` in `out.board`. Rules row: "the band head draws the raft's mark", mutant "band head without the mark".
- board.spec: seed a raft claim, for example `rafts/R0010/R0010.md` with a `preparing-…` stamp and `issues:` naming prepared members, beat by `other` at an early epoch. Assert `itemOf(model, "R0010").heartbeat == "lost"` and its place first in `views.rafts["not"]`. Rules row: "a raft's claim reaches the page", mutant N9.
- Correct Usability: a readied raft's members carry its stamp and show it; a rafting claim shows on its band head and in the Rafts view.
- State in §1 whether a band whose raft is lost, or which holds lost cards, moves to the front of its column. If it does, add a case and a row. If not, say so in §1, Usability, the zz-rules row and the README ("first in its band").
Lesson: zz-test/seed-every-enumerated-case

### F2 [medium] (repeat of review-001 F1, in part) The refute says the served wiring is out of the steps and the size; the document still orders and counts it
Where: Implementation step 6; E6; the Size paragraph and `size: 190`; §4's c0121 row; design-refute-001 F1.
Evidence:
- The refute: "step 6 and the conditional 'the executor wires `serveBoard`' are out of the Checked criteria and out of `size`".
- The document today: step 6, "If `serve.luau` is on `main`: wire `serveBoard` as section 4 says (a cached read, never on the request path) and record it in the Verification log". E6: "Section 4 states what the executor wires when `serve.luau` is there; the reviewer reads that as reasoned." Size: "The served-board wiring (section 4, E6) adds about 40, so `size: 190`", and the frontmatter says `size: 190`.
- §4 says the served wiring is "not claimed as done" and waits for the user (Q1). Step 6 lets the landing order answer Q1 instead: if R0084 is on main, the executor wires it, with no criterion, spec case or Rules row (check.sh passes with it wired well, wired on the request path, or not at all).
- The lesson this prep added this round says "never write 'the executor decides'" (z-design/no-open-question-in-a-reviewed-design).
Critique: The Checked criteria don't depend on Q1, which is right. But the executor follows the steps, and this step decides the user's open question and ships unreviewed code. `size` feeds the raft plan with 40 lines nobody has designed.
Consequences: With step 6 gone, an executor who finds `serve.luau` on main does nothing for the served page until Q1 is answered. That is the answer-(b) state, and the refute already says `design: ready` waits on the answer.
Recommendation:
- Replace step 6 with "the served board: nothing until Q1 is answered (it is recorded in this document before `ready`)".
- Set `size` to the measured prototype (about 150) and reword E6 to "not designed: waits on Q1".
- When the user answers: for (a), add the step back together with its AC, spec cases (injected `listen`, `now`, verdict source), Rules rows and size; for (b), add a `Scope decision` line and leave the step out.
Lesson: z-design/no-open-question-in-a-reviewed-design; z-design/restated-rules-move-together

### F3 [medium] The offline rule (`PICKMAN_PUBLISH=0` or no origin: no read, no word) has no case; without it the board reads the remote under `PICKMAN_PUBLISH=0` and check.sh passes
Where: Design §3 ("`boardVerdicts()` returns nil (a page without marks, exactly today's) and reads **no remote** when … `publishing()` is false (no origin, or `PICKMAN_PUBLISH=0`)"); zz-rules Offline ("`PICKMAN_PUBLISH=0` (or a repository without `origin`) keeps every command local"); Rules and mutants (no row); board.spec.
Evidence:
- Mutant N18, `if guarded(true) then` (drops `or not publishing()`): board.spec 11 passed, 0 failed. Every case runs with an origin and with `PICKMAN_PUBLISH` unset, and the protected case returns at `guarded(true)` before `publishing()` is asked.
- I added a probe case to a scratch copy of board.spec: `./zn board` in the fixture's main checkout with `PICKMAN_PUBLISH=0` (and `ZN_NOW=LATE`), expecting exit 0, empty stderr, no mark on c0010 and unchanged `fetchcalls` and `lscalls`. On the prototype it passes (12 passed, 0 failed). Under N18 it fails: `probe.spec:348: expected nil, got "lost"`. The board fetched main and the beat branches and marked the page, silently, against the Offline rule.
- Without an origin, N18 would print `warning: board: origin/main could not be read` where §3 promises today's silent page (reasoned from the code: the first read is `netRetry("git", {"fetch", "-q", "origin", "main"})`).
- The registry branch ("origin/main's projects could not be read") is reached by no case either: the shim has no switch that makes `origin/main:z-nile/projects.toml` unreadable.
Critique: This is a stated rule of the design and an existing rule of the repository, and nothing pins it. The tempting fix is a row marked `reasoned`, but the probe shows a case kills the mutant cheaply.
Consequences: The case builds its own env (`zn()` passes no `PICKMAN_PUBLISH`). A no-origin case needs a throwaway clone in the fixture without a remote, and must not edit the shared fixture's config.
Recommendation:
- board.spec: a case "`PICKMAN_PUBLISH=0` reads no remote and says nothing" (the probe above: exit 0, `stderr == ""`, no marks, `fetchcalls` and `lscalls` unchanged).
- Optionally, a no-origin case on a clone without a remote, and a `noreg` shim switch for the registry warning.
- Rules rows: "with `PICKMAN_PUBLISH=0` or no origin the board reads nothing and prints nothing" (N18), and "an unreadable registry is one warning, no marks" (that warning replaced by `fail`).
Lesson: z-design/spec-design-correspondence

### F4 [low] (repeat of review-001 F4, in part) The refute says the whole affected set was run; E4 and E7 say it wasn't. I ran the 39 tracker specs E4 leaves out: 311 passed
Where: E4 ("the 46 promoted spec files listed under Affected specs"); E7 ("its test section selected only pickman's two docs specs … so the z-nile specs were run directly: E1 to E4"); Affected specs; design-refute-001 F4 ("the whole affected set was run on the prototype (E4, E7)").
Evidence:
- My search, from the prototype's `z-nile/`: `grep -rlE 'scripts/tracker.sh|fakecli|"zn"|/zn"' tests/acceptance tests/tooling --include='*.spec.luau' | sort | grep -vE 'acceptance/(c0042|c0118|c0073|c0048|c0052|c0057|c0082|c0111|c0115|c0119|c0259|c0114|c0116|c0117|c0120|c0183|c0184|c0185)/|c0070/board-refresh|c0053/(commands-sync|publish)|tooling/board'`. It finds 39 files E4 did not run, about 3,400 spec-seconds in the results db: c0043/rounds, tooling/dispatch-guards, c0034/locator, c0072/land, c0005/worktree, c0067/ready, c0084/spend-command, c0068/stop, c0045/workstreams, c0081/allocate, compact and remap, c0053/commands-prep, start, new and claim, c0038/deferred, c0008/done-order, c0001/tracker-lifecycle, c0044/naming, c0069/prompt, c0050/start-depends, c0239/stop, tooling/worktree-fetch, c0084/commit-phase and metrics-phases, c0059/adapt, c0046/launch, c0074/done-gate, tooling/remap-once, c0080/consequences, tooling/repo-fence, tracker-review-guards, audit-spec-left, metrics-rounds, bounded-review and raftcheck, c0165/select and c0060/retrofit.
- I ran all 39 on the prototype: 311 passed, 0 failed. The runner's `sweeper: processes keep appearing` line also appears for the unrelated `tooling/raftcheck` alone (exit 71, 3 passed): the host's load, not c0276.
- `./zn check c0276` in the clone: AC1 6/0, AC2 11/0, AC3 126/0 (14 files), AC4 pass. The three "FAIL" lines are the same sweeper exit.
- Together with round 001's 11 docs readers (83 passed; the docs haven't changed since 2d999311), nothing turns red. But the document still claims a narrower run than the refute says, and E7's statement that the gate selected no z-nile spec for an engine change is left unexplained.
Critique: No defect found. The record is wrong, and it's the record the next reader of `Overrides: none` trusts. The lesson this prep added (z-design/measure-paths-fixtures-take) asks for "the whole affected set run rather than a hand-picked list".
Consequences: none.
Recommendation: Record in E4 the run of the 39 (or of the whole z-nile suite) with its counts, and paste the search that lists the affected publishing specs into Affected specs. Correct the refute's sentence in the next refute. Say why `z-nile/check.sh --affected` selected no z-nile spec on the prototype, or drop that sentence.
Lesson: zz-review/lists-paste-their-search

### F5 [low] check.sh's AC2 and AC3 labels don't say what their specs check
Where: check.sh lines 13-14; the document's AC2 and AC3.
Evidence:
- AC2's label stops at "unreadable heartbeats build the page without marks, the build succeeding with one warning; a protected checkout …". It leaves out the unreachable origin, the vanished document, the malformed beat branch and "a rebuild does not fetch main a second time", all of which the document's AC2 names and board.spec checks.
- AC3's label still says "in the spec runner, a protected checkout, the board reads no remote". The document's AC3 was corrected to "fixture repositories are not, and read the verdicts on every rebuild" (review 001 F4 asked for both).
Critique: `./zn check` prints the label, and the next reader judges AC3 by it.
Consequences: none.
Recommendation: Copy the document's AC2 and AC3 text into the two labels.
Lesson: z-design/spec-design-correspondence

### F6 [low] The page case's "lost work leads its band in the drawn column" can't fail
Where: verdicts.spec lines 264-267.
Evidence: Band 1 is `c0010,c0020,c0030` and the lost card is c0010, which is first before and after `withVerdicts`. Mutant N21, the page drawing each band's ids sorted (`b.ids.slice().sort().forEach(…)` in `renderBoard`), gives verdicts.spec 6 passed, 0 failed. A page that undoes lost-first on the default view therefore passes AC1.
Critique: The comment claims a rule the assertion can't observe.
Consequences: none.
Recommendation: In the page case, make a later id the lost one (for example c0030 lost and c0010 parked) and assert c0030 is drawn before c0010. Add a row "the board draws each band in the model's order" with N21.
Lesson: zz-test/no-vacuous-pass

### F7 [low] The document's types and messages disagree with the prototype it cites
Where: §1 (`Verdict` "a heartbeat.Verdict satisfies it"), §3 (`local boardVerdicts: (fresh: boolean) -> { heartbeat.Verdict }?`, the first failure bullet), §2 ("a page without verdicts is drawn as before"), the zz-rules board row.
Evidence:
- E7 found that a `{ heartbeat.Verdict }` is not a `{ board.Verdict }` in Luau, and the prototype returns `{ board.Verdict }?`, copying three fields. §1 and §3 still state the old type.
- §3's bullet "the fetch of main or the registry" gives one message; the prototype prints a second, `origin/main's projects could not be read`, for the registry.
- The zz-rules row says the reads are "one fetch of main and of the heartbeat branches … by `./zn board` and by every rebuild". A rebuild skips the fetch of main.
- `card()` now writes `"</span> " + mark(i) + "<br>"` where it wrote `"</span><br>"`, so every card gains a space even without verdicts. c0118's specs pass, so this is a wording fix, not a regression.
Critique: An executor who follows §1 and §3 hits the type error E7 already paid for.
Consequences: none.
Recommendation: Align §1 and §3 with the prototype's type and both texts, say "a rebuild reads no fetch of main" in the zz-rules row, and drop the space when there is no mark (or reword §2).

### F8 [low] c0284 (board shows provenance) is missing from §4's writers table
Where: §4.
Evidence:
- c0284's capture (origin/main 11fae0e1): "it shares board.luau with c0276 (board shows lost work) and R0083 (c0118): it adds to the board without changing their signatures".
- Its hand-off (`.worktree/prep-ticket-provenance`, `z-nile/.tracker/issues/c0263/experiments/split/c0284/design.md:9`) passes provenance "into `board.collect` as an optional argument after R0083's `facts`", adds a "Provenance" section to the item view, and expects "its `buildBoard` will compose `collect`/`withVerdicts`/`render`".
- My search for other writers, `grep -rlE "engine/board\.(luau|html)|buildBoard|refreshBoard"` over every prep worktree's issue documents, found only c0118, c0121, c0180, c0276 and that hand-off.
Critique: The two designs touch different signatures (`collect`'s fourth parameter, `build`'s fourth) and different panes, so they don't collide. But the table claims to name every writer.
Consequences: none.
Recommendation: Add a c0284 row (captured, draft): it adds `collect`'s optional fourth parameter and a pane section; c0276 adds `build`'s fourth and `withVerdicts`; no shared line; free order.
Lesson: z-raft/interface-names-every-writer

### F9 [low] The real cost per publish isn't stated: about 0.6 s, and 1.2 s while any claim is stale
Where: Scalability; E7.
Evidence: From the real checkout, read-only, three runs each: `git ls-remote origin 'refs/heads/hb/*'` took 0.62 to 0.72 s, and `gh pr list --state open --json title,headRefName --limit 200` took 0.48 to 0.57 s. Every publish, `land` and main-checkout `sync` now pays a fetch of the beat branches of about that size, plus `gh pr list` whenever any claim in the repository is stale, plus a `git show` and a `git log -S` per claim (c0265 E4: 18 ms each). Spend rows and claims are publishes. E7 measured the fixtures only (+10%).
Critique: The design calls the cost "intended", which is a fair reading of "the board's own rebuilds keep the marks". But the user sees it as latency on every tracker command and hasn't been given the number.
Consequences: A cheaper option (reuse verdicts read within the last N seconds, cached in the main checkout's `.cache`) brings staleness up to N seconds and a cache file, and is the user's call.
Recommendation: Put the measured per-publish cost in Scalability and in the report to the user, beside the +10% gate number. Offer the cache as an option rather than choosing it.

Lessons added this round (harvest.md): z-design/no-open-question-in-a-reviewed-design and z-design/measure-paths-fixtures-take are both lessons another raft could fail, not restated findings. This draft fails both of their checks (F2, F4).

Candidate lesson for the lead (from F1): when a design marks items on the board, list every claim kind (an issue's claim, a raft's own rafting claim, a readied raft whose members carry the stamp) and every place each kind is drawn on the default view. Check: on the view the page opens on, where does a lost claim of each kind show?

Verdict: changes

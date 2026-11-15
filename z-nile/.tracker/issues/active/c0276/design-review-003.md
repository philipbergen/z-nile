# Review 003: c0276 (design mode)
Inputs: prep worktree `.worktree/prep-board-shows-lost-work` at 5d8fb89f with the working-tree c0276.md (sha256 d371a933dc60…), check.sh (e128f9515cec…), acceptance/board.spec.luau (eb25196e02ef…), acceptance/verdicts.spec.luau (895752beaa44…), design-review-001/002, design-refute-001, design-refute-002 (c75df0faabcf…), harvest.md (024de32b2ab5…) and the three lessons it adds; prototype origin/proto-c0276 5f51d6b7 (its check.sh and both specs are byte-identical to the prep's); `git diff origin/proto-c0265-raft origin/proto-c0276 -- z-nile/engine z-nile/README.md z-nile/skills` (157 added, 12 removed lines); c0265's document, check.sh and `experiments/envelope.patch` at origin/prep-work-heartbeat 28e2c906; the c0274, c0275, c0276 and c0277 hand-offs; origin/R0084-board-live-server d46bd5f8 (PR #272, draft); origin/omarchy-board-app (PR #243); c0180.md on main e5cea112; `./zn capture c0276` (8577a496, a confirmed capture: title, Problem and Non-goals unchanged, Solution only gained detail). Main moved 52 commits past the prototype's base 1758cf21; of the files the specs load only `tests/lib/fakecli.luau` changed (modes of the model-CLI fake that neither spec uses). All runs were in scratch clones of 5f51d6b7 with origin removed, under /private/tmp/claude-501/-Users-philipbergen-code-pickman/3fbf9326-e053-49c8-ab1e-bfbc221fe8f4/scratchpad (`rv3c` the bare prototype, `rv3m` the mutants, `rv3e` the prototype with c0265's envelope.patch; scripts in `scripts/`: `mut.py`, `muts.json`, `muts2.json`). Nothing in the repository was edited. Baseline on the bare prototype: verdicts.spec and board.spec 19 passed, 0 failed.
Dropped from review-002: F1, F2, F3, F6, F8, F9 (fixed; re-run one at a time: N9 board 12p/1f at :174, N10 verdicts 5p/1f at :269, N18 board 12p/1f at :338, N22 board 12p/1f, N21 verdicts 5p/1f, M8 board 12p/1f, Mh board 12p/1f, M12 board 12p/1f, M9 board 6p/7f, Mg board 12p/1f), F5 (labels match the document's ACs). F4 and F7 are answered except for record lines, which F5 below carries. Q1 (the served board and the c0257 app), the band-head decision and the per-publish latency are the user's and handled as stated: not findings.

### F1 [high] A board that moves `nobeat` cards ahead with the lost ones passes AC1 and AC2; "parked, stale and nobeat never move" has no Rules row and no case for `nobeat`
Where: Design §1, Order ("Parked, stale and `nobeat` cards never move: only lost work is promoted, as in `./zn status`"); AC1 ("puts lost work first inside each bucket and band, longest silent first, the rest as before"); verdicts.spec lines 189-192 ("a parked or stale claim never jumps ahead of the rest"); Rules and mutants (no row for this rule).
Evidence:
- Mutant X12 in `board.luau`'s `ordered`: `local al, bl = am ~= nil and (am.heartbeat == "lost" or am.heartbeat == "nobeat"), bm ~= nil and (bm.heartbeat == "lost" or bm.heartbeat == "nobeat")`. verdicts.spec: 6 passed, 0 failed. board.spec: 13 passed, 0 failed.
- Controls on the same line: X14 (parked promoted) verdicts 3 passed, 3 failed; X15 (stale promoted) 4 passed, 2 failed. The kind the "never jumps ahead" case leaves out is exactly the one that survives.
- A probe spec in the scratch clone (`withVerdicts` over the Not-ready bucket and one band `c0010,c0020,c0030,c0050`, with c0010 lost at 2130 s and c0050 `nobeat` at 90000 s): the prototype gives `ORDER c0010,c0020,c0030,c0050 BAND c0010,c0020,c0030,c0050`; X12 gives `ORDER c0050,c0010,c0020,c0030 BAND c0050,c0010,c0020,c0030`.
- Why nothing sees it: verdicts.spec's ordering cases seed lost, parked and stale only; its page case marks c0050 `nobeat` but c0050 is alone in the loose band and the bucket order isn't asserted there; board.spec's c0090 is `nobeat` and is never positioned.
- What it does on landing day: `git grep -lE "^status: (preparing|active)-" origin/main | grep -v "/done/" | grep -E "/(c|f|d|R)[0-9]{4}\.md$" | wc -l` gives 43 claims, every one made before the heartbeat lands. By c0265's rule each reads `nobeat` once it is 900 s old and has never beaten, with a silence of days. X12 puts all of them ahead of the actually lost claims in every bucket and band, which is the opposite of the capture's "lost work first … as `./zn lost` and `./zn status` order it" (`status` promotes only `lost`).
Critique: The rule is stated, it decides what the board looks like the day it lands, and AC1 passes without it. The tempting fix is to add a `nobeat` verdict to the existing case. That still passes X12 when the `nobeat` card is already first in the old order, or when its silence is shorter than every lost card's and nothing non-lost sits between them. Round 001 F2 found the ordering seeded in one bucket only; this round finds the kept kinds seeded in part. The mechanism (one hand-picked example per rule) is what keeps leaving a value out.
Consequences: None in the code. `unknown` maps to `stale` and `live` adds no mark, so the kinds the case must cover are parked, stale, unknown and nobeat.
Recommendation:
- In verdicts.spec (a spec, because it pins a rule the gate must keep after `done`), make the "never jumps ahead" case table-driven over every kept kind: parked, stale, unknown and nobeat.
- For each kind, place the card last in the old order of a bucket and of a band, after an unclaimed card. Give it a longer silence than one lost card earlier in that order. Expect the lost card first and every other card exactly in its old order.
- Add a Rules row "parked, stale, unknown and nobeat cards keep their place" with X12, X14 and X15 as its mutants (run).
Lesson: zz-test/seed-every-enumerated-case

### F2 [low] The drawn order of the Rafts and Issues lists is unpinned: a page that sorts each list group by id passes AC1 (the hole review 002 F6 found for bands, in the lists)
Where: verdicts.spec, page case (lines 214-276); board.html `renderList`; AC1 ("the page draws … on list rows of issues and rafts").
Evidence:
- Mutant X4 in `renderList`: `var groupIds = model.views[view][g].filter(inProject).sort();`. verdicts.spec: 6 passed, 0 failed.
- The page case checks list rows only by presence (`has(out.issues, …)`, `has(out.rafts, …)`), and checks order only in the Board view's band (lines 271-274, which kill N21).
- In that case the model's order is `views.issues["not"]` = c0030, c0010, c0020, c0050 and `views.rafts.ready` = R0040, R0030, so a drawn list sorted by id undoes lost-first.
Critique: These lists are the buckets the capture names ("lost work first within its bucket"), and the page is where a person sees them. Round 002 pinned the drawn order in the one place it pointed at.
Consequences: None.
Recommendation:
- In the page case, assert the drawn order wherever the page draws an ordered list from the model:
  - the Issues view's Not-ready group: c0030 before c0010 before c0020;
  - the Rafts view's Ready group: R0040 before R0030;
  - the band already done.
- Add a Rules row "each list group is drawn in the model's order" with X4.

### F3 [low] The lost mark is hard to read in dark mode, and it touches the stage badge in list rows and pane headings
Where: Design §2 ("lost in the alert colour"); board.html `.mark.m-lost`, `renderList`, the issue and raft pane headings; OC1.
Evidence:
- `.mark.m-lost { border-color: #c0392b; color: #c0392b; … }` is hard-coded. The page redefines its tokens under `@media (prefers-color-scheme: dark)` (board.html:9-10, `--bg: #15171a`), and `.card` draws on `var(--bg)`.
- WCAG contrast, computed from relative luminance (scratch python): #c0392b on #15171a is 3.3:1, and on #fff it is 5.44:1. The page's own muted grey on the dark background is 7.03:1. So the mark that matters most is below 4.5:1 for 11 px text in dark mode.
- List rows draw `badge(it.stage) + mark(it) + copy`, and the panes draw `badge(issue.stage) + mark(issue) + "</h2>"`. In both, two bordered pills sit side by side with no space between them. Cards and band heads put a space before the mark.
Critique: The capture's first outcome is that the board shows the verdict. OC1 looks at the page in whatever mode the person happens to use.
Consequences: A CSS-only fix leaves the sequestered strings (`'<span class="mark m-lost">lost 35m</span>'`) and c0118's page strings unchanged.
Recommendation:
- Add an `--alert` token to `:root`, with a dark value measured at 4.5:1 or more on #15171a, and use it in `.mark.m-lost`.
- Give `.mark` a `margin-left` in CSS rather than a space in the strings.
- Make OC1 look in both colour schemes.

### F4 [low] Section 4 says c0265 and c0180 place `boardVerdicts`; neither document does
Where: §4, c0180 row ("adds `boardVerdicts` beside `judgeAll` (heartbeat code, which c0265 already places)", "c0180 places it with c0265's").
Evidence:
- `git show origin/prep-work-heartbeat:z-nile/.tracker/issues/c0265/c0265.md | grep -c c0180` gives 0.
- `grep -cE 'heartbeat|c0265|c0276|boardVerdicts|judgeAll' z-nile/.tracker/issues/c0180/c0180.md` gives 0.
- c0180's layout puts `buildBoard` in `boardrefresh.luau`, `guarded` and `publishing` in `guard.luau`, and `originTree` and `originRoots` in `origin.luau`. Its R4 forbids a `guard`/`boardrefresh` require cycle. Its port rule sends a later `main.luau` change "into the module that now holds that code (the split's layout says which)", and the layout has no home for `judgeAll` or `boardVerdicts`.
Critique: The next c0180 prep will read this row as settled. In fact the placement is open, and it touches R4: `buildBoard`, in `boardrefresh`, would call code that needs `guard`, `origin` and the heartbeat reads.
Consequences: None for c0276's own specs.
Recommendation: Reword the row to say what is true:
- c0180's layout has no home for c0265's heartbeat edge or for `boardVerdicts`;
- whichever lands second places them, without closing R4's cycle (for example, `boardrefresh` takes the verdict reader as an argument rather than requiring it).
The lead passes the same note to c0180 (a capture or the report), as its role allows.
Lesson: z-design/quote-other-preps-before-promising

### F5 [low] The record lags the prototype: case counts, c0265's fifth spec, the docs readers, E7's sentence and the "drawn as before" claim
Where: Unknowns & experiments E1, E2, E3, E4, E7; §2 ("a page without verdicts is drawn as before"); §5 ("is byte-identical"); Implementation step 7 ("c0265's five specs"); design-refute-002 F4 and F7.
Evidence (my runs on the scratch clones):
- **Case counts.** E1 says board.spec has 7 cases and E3 says 70 passed. Both predate review 002's cases (the R0020 rafting claim, `PICKMAN_PUBLISH=0`, the registry). board.spec has 13 cases now. c0265's four specs and c0276's two, with the envelope applied: 72 passed, 0 failed, 6 files.
- **c0265's fifth spec.** Step 7 asks for "c0265's five specs". E2 and E3 record four; the fifth is `proofs/race.spec.luau`, c0265's AC4. On the bare prototype it gives 8 passed, 0 failed. `./zn check c0265` on the envelope clone gives AC1 21/0, AC2 17/0, AC3 15/0, AC4 8/0, AC5 pass. Its four FAIL lines are the runner's `sweeper: processes keep appearing` exit 71 on this loaded host, which round 002 also saw on an unrelated spec.
- **Docs readers.** E4's docs-reader run predates round 002's edit of the zz-rules board row (`git diff --stat 2d999311 5f51d6b7 -- z-nile/README.md z-nile/skills` shows zz-rules, 1 line changed). Every reader of the two docs and of the two board files, found by `grep -rlF -e "zz-rules/SKILL.md"`, `-e "z-nile/README.md"`, `-e "README.md"`, `-e "engine/board.luau"` and `-e "engine/board.html"` over `tests/acceptance` and `tests/tooling` (31 spec files, leaving out c0118/docs, which runs in AC3's set): 215 passed, 0 failed. AC3's set with c0073 and `tooling/board-review`: 163 passed, 0 failed, 19 files. `Overrides: none` holds.
- **E7's sentence.** E7 still says the `--affected` gate "selected only pickman's two docs specs". Review 002 F4 asked for it to be explained or dropped, and refute 002 F4 doesn't answer it.
- **"Drawn as before".** Refute 002 F7 says the extra space "is named". §2 still says "a page without verdicts is drawn as before" and §5 "byte-identical". In the prototype, a card without a mark draws `</span> <br>` (it was `</span><br>`), and a band head of a known raft gains a trailing space.
Critique: These records are what the next reader of `Overrides: none` and the layer rule trusts.
Consequences: None.
Recommendation:
- Record the counts above in E1, E3 and E4, and name race.spec and `./zn check c0265` in E2 and E3.
- Drop E7's `--affected` sentence or explain it.
- Reword §2 and §5: "the model is byte-identical; the drawn card and band head gain one space, which no promoted string pins".

Lessons added this round (harvest.md): z-design/every-claim-kind-on-the-default-view is a lesson another raft could fail, not a restated finding. `./zn lessons --check` passes (268 lessons).

Candidate note for the lead (from F1), on zz-test/seed-every-enumerated-case: a "keeps its place" rule is pinned only when every kept value is seeded at the position and with the value a wrong rule would move. Here, each kept kind needs a longer silence than a lost card and must sit after a card it could jump. Check: for each value the rule says never moves, would a rule that moves it change this case's expected order?

Verdict: changes

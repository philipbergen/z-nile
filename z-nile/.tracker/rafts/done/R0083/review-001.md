# Review 001: R0083 (code mode)
Inputs: HEAD 16b5b0ac (branch R0083-project-board, PR #263) against origin/main 1e0f51bb (merge base 1873ab3e); `git diff origin/main...HEAD` (20 files); c0118.md, R0083.md, c0118's `check.sh` and `acceptance/`; prototype `proto2-c0118` tip 6bb217fb (base c1b429a9).

Evidence run by the reviewer:
- Carried change = prototype: `git diff c1b429a9 6bb217fb -- <the 17 paths>` and `git diff origin/main...HEAD -- <the 17 paths>` are 1933 lines each and identical apart from `index`/`@@` lines. `git diff 6bb217fb HEAD -- <the 17 paths>` touches 4 files (main.luau, zz-rules SKILL.md, c0172 narrowed.spec, inputs.tsv), and those hunks equal `git diff c1b429a9 origin/main` on the same files, which is R0086 (11df0fd0) on main. `git merge-base --is-ancestor 6bb217fb origin/proto2-c0118` succeeds. Nothing else is carried. Main moved by tracker-only commits since the merge base (spend rows, c0269), none on these paths.
- Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**' …` lists nothing. The only change under c0118's folder is the Verification log (c0118.md +8) and spend.md.
- `./zn check c0118`: 10/10, rc 0 (AC9 read origin's main from https://github.com/philipbergen/pickman.git).
- `z-nile/check.sh --affected`: **GATE PASSED (affected)**, rc 0. Engine paths changed, so every spec ran. Format, lint, types, builds and skills are clean. pickman 1815 passed, 0 failed. z-nile 1644 passed, 0 failed (240 spec files). Each of the five arcade homes 25/25. Gate wall time 1096 s. The "FAIL" lines inside z-nile's section are the fixture runs nested inside the gate's own specs (c0165), not the suite's result.
- `./zn board --out .cache/board-review.html`: 6.62 MB, 0.93 s wall. Main checkout's own page (built by main's code) is 6.44 MB, so c0118 adds about 190 KB. Model: 7 projects in registry order, `history: true`, `problems: []`, launched rafts R0061, R0071 and R0083 (with branch and worktree), z-nile columns ticket 32 / design 18 / raft 13 / ready 9 / run 4 / done 75 (1 inside 24 h), pickman 16/1/5/0/0/57.
- Scratch probe (`./zn run --time 60 -- lune run <scratchpad>/probe.luau`): `board.collect` over a fixture where a done issue's `raft:` names a missing raft and has a `design-review-001.md` does not crash (an unknown raft is cleared to nil at board.luau:844). I raised no finding on it.
- JC1: headless Firefox (`-headless -window-size 1440,900 -screenshot`, a profile with `ui.systemUsesDarkTheme` 0 or 1, run through `./zn run --time 120`). Screenshots of the pickman Board (dark), the z-nile Board (light), the z-nile charts (light and dark; the board was scrolled to its bottom by a script line added to a scratch copy of the page), and the Rafts view via `#R0083` (light). This is a real browser engine at 1440×900 but no interactive session: I saw no hover tooltips and did no keyboard walk.

### F1 [high] JC1 fails: the board's charts are drawn at half scale, so the axis and legend text is about 5.5 px, and the token axis has no visible unit
Where: z-nile/engine/board.html:67-68 (`.chart { width: 320px }`, `.chart text { font-size: 11px }`, which the board's charts inherit from Stats), z-nile/engine/board.luau:770-776 (`chartSvg`: the scaled unit goes only into `chart.svg`'s `opts.unit`), z-nile/engine/chart.luau:210 (`opts.unit` appears only in each bar's `<title>` tooltip) and :127 (a legend only from 2 series).
Evidence: `chart.svg` draws in a 640×200 viewBox, and the page shows it 320 px wide, a 0.5 scale. Its 11px text therefore renders at about 5.5 CSS px. In the 1440×900 screenshot of the z-nile Board, the tick labels (0–100, 0–30), the week labels ("Aug 10 … Nov 2") and the legend ("Design reviews", "Code reviews", "claude-opus-5-5", "unrecorded model") are unreadable at 1×. They can be read only after a 2× crop, and even then "Aug 24 Aug 31" and "Oct 12 Oct 19" sit edge to edge.

The tokens axis is scaled by `boardview.scaled` (§7, E5), but the unit appears nowhere a reader can see:
- z-nile's axis reads 0–30, which is M tokens.
- pickman's axis reads 0–8000, which is k tokens (its tooltip says "unrecorded model, Oct 26: 7565.7 k tokens").
- The two tabs look comparable and are off by 1000×.
- pickman's tokens chart has a single series ("unrecorded model"), so it has no legend at all. Nothing visible says which model the bars are.

The rubric's "both charts have legible axes" fails, and that is an unmet acceptance criterion. The rest of the rubric passes: see the Judged criteria section.
Critique: The tempting fix is to bump `.chart text` or `.chart` width globally. That also resizes the Stats charts (c0073), whose layout puts several 320 px figures in a row inside `#stats`, which has `max-height: 72vh`.
Consequences: Scope any fix to `#charts` so Stats is untouched. If the board's charts are rendered 640 px wide, two side by side need about 1290 px. The board area beside the 30em pane and the project tabs is about 880 px at 1440, so they wrap to two rows, and the charts sink further below the longest column (z-nile's ticket column is 32 cards). A visible unit is a new piece of model data per project, chart and range, because `boardview.scaled` picks k or M per range.
Recommendation:
- Size the board's charts in `#charts` only, for example `#charts .chart { width: 100%; max-width: 640px }` with the two figures stacked or in a two-column grid that drops to one column under about 1300 px, so the 11 px text renders at 11 px or more at 1440 wide.
- Carry the scaled unit in the model beside each SVG (for example `charts[p].units.tokens[range]`, set from `chartSvg`'s second result) and put it in the figcaption ("Review tokens by model, M tokens"). An alternative is an axis title drawn by the board's caller.
- Name the series in the caption, or force a legend, when there is one series, so a one-model chart says which model it is.
- Pin it in a non-sequestered spec: in `tests/tooling/board.spec.luau` or a new tooling spec, the model carries a unit per tokens range ("k tokens" for a fixture week over 10,000, "M tokens" over 10,000,000), and the rendered figcaption contains it.
- Re-shoot 1440×900 light and dark, and record it in the Verification log.

### F2 [medium] `problems` is collected but nobody can see it: a spend.md that `ledger.parse` rejects now silently drops every row of that issue from Stats, the cards and the charts, and a compaction-map warning is invisible
Where: z-nile/engine/board.luau:258-275 (`spendRows`: a file that does not parse gives `{}` and a line in `problems`), :811-815 (history warnings into `problems`), :1161/:1179 (sorted into the model). `grep -n problems z-nile/engine/board.html z-nile/engine/main.luau` finds nothing: the page never shows it and `cmd.board` (main.luau:5636-5662) never prints it.
Evidence: Before this change, the old seven-column reader skipped only the malformed rows of a spend.md. Now one row that `ledger.parse` refuses (a hand edit, a merge-conflict leftover, a future column) changes several things for that issue at once:
- its minutes and lines vanish from Stats;
- its card says "0 min, 0 tokens";
- its review tokens leave the tokens chart, and its done date can fall back to undated.

The only trace is a string inside the embedded JSON. The same goes for §5's fail-closed history warning ("a compaction map could not be read …"): the Design says "the board adds it to `problems`", and then nothing reads `problems`. The Regression guard sells this as "named in `problems` instead of half-read". Today `problems` is empty on the real tree, so nothing is wrong yet. It is a silent-failure path waiting for its first malformed row.
Critique: The tempting fix is a `console.warn` in the page. Nobody opens the console.
Consequences: Printing to stderr from `./zn board` also prints during the main checkout's refresh after every `sync` and publish (c0070). It must stay a warning, exit 0, and not break `sync`'s output contract. A page banner is part of the static page that c0121 re-renders, so `znBoard.load` must redraw it from the new model.
Recommendation:
- Show `model.problems` on the page: a muted note above the columns, "N files could not be read", listing them, redrawn by `renderBoard` so `load` refreshes it.
- Print each problem to stderr from `cmd.board` as `warning: <problem>`, keeping exit 0.
- Add a non-sequestered spec case: a fixture spend.md with one bad row gives a visible note in the rendered page and a stderr line from `./zn board -O`, and the build still exits 0.

### F3 [medium] The board keeps its own copy of the round-file patterns, so "one rule with `metrics`" holds only by coincidence
Where: z-nile/engine/board.luau:740-749 (`reviewFiles` filters names with `^design%-review%-%d+%.md$` and `^review%-%d+%.md$` before `boardview.rounds` ever sees them), against c0118 §6 ("`metrics` counts its rounds through the same `boardview.rounds`, so the chart and the tables share one rule") and Maintainability ("A new review kind is one pattern in `boardview.rounds`, which `metrics` shares"). Design review 006 F3 and `metrics.spec` forbid exactly this copy in `main.luau`'s counters, and the board was left out.
Evidence: Suppose a new round kind is added the way Maintainability says, as one pattern in `boardview.rounds`:
- `metrics` counts it, because main.luau:5226-5232 and :5560-5567 pass every file name of the folder.
- The board's rounds chart and a raft pane's "review rounds" do not, because `reviewFiles` dropped those paths before calling `rounds`.

The two diverge with every spec green, because `view.spec` tests `boardview.rounds` on paths it builds itself and `model.spec`'s fixtures use only today's two names.
Critique: Copying the new pattern into `reviewFiles` too is the tempting fix. That is the duplication that caused the drift.
Consequences: Without the filter, `files[raft]` holds every file name of each raft and member folder (spend.md, check.sh, harvest.md, refutes …). That is a few hundred strings per build, negligible. `boardview.rounds` already ignores non-matching names.
Recommendation:
- Make `reviewFiles` collect every file path in the folder, as `designRoundsIn` and `codeRounds` do, and leave the counting to `boardview.rounds`.
- Pin it in a non-sequestered tooling spec the way `metrics.spec` pins the counters: `board.luau`'s source, read without comments and strings, names no `review%-` pattern.

## Judged criteria (code mode only)
- JC1: fail. I observed headless Firefox 1440×900 screenshots of this branch's page, which was built in the R0083 worktree with the real tree. This is the same tree as the main checkout's page, but not that file.
  - Passing: the six columns fit beside the 30em pane with no horizontal scroll. The Done column ends near x≈1005 and the pane starts near x≈1030. The tracks are `minmax(9em, 1fr)`, about 796 px against about 880 px available.
  - Passing: every band's head names its raft (id link, title and status badge, for example "R0068 Review lessons to the step · active").
  - Passing: cards wrap within their column with no overlap. Only one title word on the real tree is over 14 characters ("Eight-direction").
  - Passing: the dark scheme keeps the series apart. Design is purple and code is blue; claude-opus-5-5 is blue and "unrecorded model" is grey (#4a5058 on #15171a, low contrast but distinct).
  - Failing: the charts' axes and legends are not legible (F1). Their text renders at about 5.5 px, and the tokens axis has no visible unit, so z-nile's "30" (M) and pickman's "8000" (k) are not comparable. A single-series tokens chart (pickman, "unrecorded model") has no legend.
  - Not observed: hover tooltips, the keyboard walk and a real interactive window. The node specs (AC4) cover the behaviour.

Lesson candidates (for the lead to harvest; I write no lesson file):
- zz-review / z-design: a Judged criterion about legibility is checked at the rendered size, not in the SVG's own viewBox. Check: what CSS width does the page give a `viewBox` drawing, and what pixel size does its text come out at? It came out at 5.5 px here, and prep's Quick Look dump could not show it.
- zz-arch/one-reader-per-format: a rule "shared through one function" is undone by a pre-filter at a call site. Check: does any caller filter the inputs with the shared function's own patterns before calling it?

Verdict: changes

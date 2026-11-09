# Review 003: R0083 (code mode)
Inputs: HEAD 28d99fd0 (branch R0083-project-board, PR #263); `git fetch origin main` (FETCH_HEAD cfc60896, merge base 1873ab3e); `git diff origin/main...HEAD` (29 files); the fix delta `git show 28d99fd0` (board-review.spec, c0118.md, harvest, a lesson note); review-001/refute-001, review-002/refute-002; R0083.md, c0118.md, c0118's `check.sh` and `acceptance/`.
Dropped from review-002: F1 (fixed: the page is driven in node and every mutant of it below is red), F3 (fixed in §2 and the log; a leftover line is F3 below). Repeated: F2 (as F1 below, with new evidence).

Evidence run by the reviewer:
- Sequestration: `git diff --find-renames=100% --name-status FETCH_HEAD...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` lists nothing.
- `./zn check c0118` in the worktree: AC1 to AC10 PASS, rc 0 (AC9 read origin's main from https://github.com/philipbergen/pickman.git).
- A scratch repository made from `git archive HEAD` under `.cache/rev3-R0083` (its own `git init`, committer `@example.invalid`); every run there through `./zn run`. Base: `lune run tests/run -- tests/tooling/board-review.spec.luau` 5 passed, 0 failed.
- Mutants (each applied alone to the scratch copy, then `git checkout -- .`; the script is a one-off in my scratchpad), each leaving the words the old pins searched for in place:
  - Ma `pr.length ?` → `pr.length > 1 ?` (board.html:214): **red** (spec:184).
  - Mb the two `ch.captions.*[range]` swapped (board.html:221-222): **red** (spec:150).
  - Mc `if (problemsEl) {` → `if (false && problemsEl) {` (board.html:212): **red** (spec:184).
  - Mi the note drawn only on the first render (a once-flag on `problemsEl`): **red** (spec:186, `expected "", got "<p class=…"`): the redraw on `znBoard.load` is pinned.
  - Md a later `#charts .chart { width: 320px; }`, and Md2 `#board #charts .chart { width: 320px; }`: **red** (spec:164, count 2). (A selector not containing `#charts .chart {` would pass; that is the CSS tripwire review 002 already left to JC1, not repeated.)
  - Me review 002's `[-]` filter in `reviewFiles`: **red** (spec:213).
  - Mf, Mg, Mh: **green**, see F1 and F2.
- Regression, in the scratch copy: `tests/tooling/{board,board-review,metrics-rounds,tracker-guarded,status-fresh}.spec`, c0043 rounds, c0045 workstreams, c0048 board-docs, c0053 commands-sync, c0067 ready: 65 passed, 0 failed (the same run's 13 "could not load spec" lines were directories I passed by mistake; rerun as files next). Every c0042 and c0107 spec, c0057 guard/open, c0070 board-refresh, c0073 board-stats, c0084 metrics-phases, c0111 metrics-lessons, c0114 layout/trail-move, c0115 layout/readme, c0116 issue-design/recombine, c0120 finished/trail-home, c0172 narrowed, c0259 readme: 139 passed, 1 failed. The failure is c0120 `finished.spec`:979 "the tree before the move is not known: no commit removed tracker/rafts/done/R0001/check.sh: the history is shallow": my scratch repository has one commit, so it has no history to read; it is the fixture, not the raft (the author's full gate on this head ran it green). I did not rerun the gate, as briefed.
- Lune module identity, for F1's Recommendation: a probe in the scratch copy requiring `@znile/engine/boardview` and, from `engine/`, `./boardview` gets the same table (`rawequal` → true).
- JC1: `./zn board --out .cache/board-rev3.html` in the worktree (6,625,368 bytes; model `problems: []`; token captions z-nile ", M tokens", pickman ", k tokens: unrecorded model", the five others ", tokens"; every rounds caption ""). Scratch copies of that page with one script line each (click a project tab; scroll `#charts` into view; one `znBoard.load` of the model with two problems), shot with `/Applications/Firefox.app/Contents/MacOS/firefox -headless --no-remote --profile <p> -window-size 1440,900 -screenshot`, profiles with `ui.systemUsesDarkTheme` and `layout.css.prefers-color-scheme.content-override` set light or dark, each through `./zn run --time 150`. Shots read: pickman Board light, z-nile Board dark, z-nile charts light and dark, pickman charts light and dark, arcade charts dark, pickman Board light with two problems.

### F1 [low] The round-rule pin still has spellings that pass: a prefix test with `:sub`, or a single-quoted pattern in a helper outside `reviewFiles` (repeat of review-002 F2)
Where: z-nile/tests/tooling/board-review.spec.luau:200-220 (the body of `reviewFiles` scanned for match/find/gsub/`string.sub` calls; string literals collected with `'"([^"\n]*)"'`, double quotes only); the code it guards is z-nile/engine/board.luau:745-752 and :1120.
Evidence: in the scratch copy, each run against `tests/tooling/board-review.spec.luau`:
- Mf, `reviewFiles`' loop body becomes `if name:sub(1, 7) == "review-" or name:sub(1, 14) == "design-review-" then table.insert(into, …) end`: **5 passed, 0 failed**. `:sub(` is not in the forbidden list (only `string.sub`), and `"review-"` holds no `%`, `[`, `]`, `^` or `$`.
- Mg, a helper `local function isRound(n) return string.match(n, '^review[-]%d+%.md$') ~= nil or string.match(n, '^design[-]review[-]%d+%.md$') ~= nil end` above `reviewFiles`, which calls `if isRound(name) then … end`: **5 passed, 0 failed**. The helper is outside the extracted body, and single-quoted literals are never collected. The lesson the author harvested review 002's F2 into, zz-test/source-text-pins-read-the-code, says "collect string literals (quoted, backtick, long-bracket)" and "a constant hoisted out of it escapes": this spec does neither.
Both mutants put back a second copy of the round-file rule beside `boardview.rounds`, which is what review 001 F3 found.
Critique: this is the third hole in the same mechanism (review 001 F3: the copy; review 002 F2: the `[-]` spelling; now `:sub` and a hoisted single-quoted pattern). Each round adds a forbidden spelling and the next round finds another. The tempting fix is to add `:sub(` and single quotes to the lists, which a backtick literal, `string.byte`, or a lookup table `{ ["review-001.md"] = true, … }` then escapes.
Consequences: a pin over the source text can never list every way to write a filter. What the rule actually is, "reviewFiles hands `boardview.rounds` every file of the folder", is behaviour, and it can be observed: `board.luau` calls `boardview.rounds(files[raft.id])` through the module table at call time (board.luau:1120), and Lune gives the spec the same table (probe above), so a spy sees the list. A spy pins the data flow, which the source pin could not (the lesson's "a text pin can't prove data flow").
Recommendation: replace the F3 case's source scan with a behaviour case in `tests/tooling/board-review.spec.luau` (not promoted, not sequestered): in the fixture, give a done raft's folder and a member issue's folder files that the rule should and should not count (`review-001.md`, `design-review-002.md`, `notes.md`, `review-x.md`, `review-001.md.bak`); wrap `boardview.rounds` (required as `@znile/engine/boardview`) with a spy that records each list it is given and calls the original, restoring it in the same case; run `board.collect`; assert the spy's list for that raft holds every file of both folders (all five names), and that `raft.rounds` equals what the original `boardview.rounds` returns for that list. Mf, Mg and Me then go red because the list loses `notes.md`, whatever the spelling. Keep `has(src, "boardview.rounds(")` if wanted; drop the literal scan or keep it only as a tripwire with a header line saying it is one. Record Me, Mf and Mg as run, red.
Lesson: zz-test/source-text-pins-read-the-code

### F2 [low] The problems note's escaping is untested: dropping `esc` passes, and a spend row containing markup is then drawn as markup
Where: z-nile/engine/board.html:215 (`pr.map(esc).join("; ")`); z-nile/tests/tooling/board-review.spec.luau:180-190 (the problems are plain text: `c0012/spend.md … unterminated`, `a/spend.md does not parse`, `history: map line`).
Evidence: Mh, `pr.map(esc)` → `pr.map(String)` in the scratch copy: board-review.spec **5 passed, 0 failed**. A problem string quotes the row: `ledger.parse` returns `not a spend row: {line}` and its siblings (z-nile/engine/ledger.luau:77-118), and board.luau:273 puts that into `problems` as `{path} does not parse: {err}`. So a malformed row whose attribution reads, say, `fix <details> parsing` would open an element in the note on the opening view, and the rest of the Board would render inside it.
Critique: the page escapes every other model string it draws (`esc` at board.html:151); this one new sink has no case that would notice the escape going. Impact is small (the page is local and built from the repository's own files), hence low.
Consequences: none beyond one more fixture string.
Recommendation: in the F2 case, add to the `two` model of the node harness a problem containing `<b>x</b> & "q"`, and assert that `out.two.problems` contains `&lt;b&gt;x&lt;/b&gt;` and not `<b>`. Record Mh as run, red.

### F3 [low] The Verification log still says "Deviations: none." above the entry that records a deviation
Where: z-nile/.tracker/issues/active/c0118/c0118.md:522 ("- Deviations: none."), followed at :524 by the Code review 001 entry that records the `captions` field, the `#problems` note and the chart sizing.
Evidence: `grep -n "Deviations: none" z-nile/.tracker/issues/active/c0118/c0118.md` → 522. Review 002 F3's Recommendation asked to replace that line; refute-002 says F3 is fixed, and the fix delta added the later paragraph but left the line.
Critique: a reader of the step-by-step log stops at "none"; the deviation is one paragraph below. Text only.
Consequences: none.
Recommendation: change line 522 to "- Deviations: see Code review 001 below (`ProjectCharts.captions`, the `#problems` note, the board's own chart size, `reviewFiles` without a pattern)".

## Rulings on refute-002
- F1: accepted. The node fake-DOM harness drives the page's own script; each of review 002's page mutants (Ma, Mb, Mc) is red on an assertion about what is drawn, and so is a no-redraw mutant (Mi) the refute did not list. The caption-less model case runs. The CSS width stays a string pin plus JC1, as review 002 said it must.
- F2: not accepted as fixed: the pin catches the `[-]` spelling but two other spellings pass (F1 above). The mechanism, not the spelling, is the problem.
- F3: accepted for §2 and the log entry; one leftover line (F3 above).
- The stderr note: settled in review 002, not reopened.

Nothing regressed in what I ran: board, history (c0042 model, c0118 AC2), metrics (c0043, c0084, c0111, metrics-rounds, c0118 AC8), Stats (c0073 board-stats, c0107), the CLI and refresh (c0042 cli, c0057, c0070), the overridden specs (c0118 AC9).

## Judged criteria (code mode only)
- JC1: pass. Observed in headless Firefox at 1440×900 on this head's page, built in the R0083 worktree from the real tree (the main checkout's own page is still main's code until this lands), light and dark:
  - The six columns fit beside the pane with no horizontal scroll (z-nile Board dark: Done ends near x≈1005, the pane starts near x≈1015; pickman Board light the same).
  - Every raft band's head names its raft ("R0066 Touch circle controls · prepared", "R0030 Suite split · prepared", "R0083 Project board · active", "R0086 Full gate at merge · done"); raftless cards form a headless last band, as Design §4 says.
  - Cards wrap inside their column with no overlap.
  - Both charts render about 630 px wide; tick labels (0–100, 0–30, 0–50, 0–8000), week labels (Aug 10 … Nov 2) and legends read at about 11 px; none clipped or overlapped.
  - A legend for every chart with two series (rounds everywhere; z-nile tokens: claude-opus-5-5 and unrecorded model); pickman's one-series tokens chart names it in the caption ("Review tokens by model, k tokens: unrecorded model"); z-nile's says "M tokens". Projects with no rows (arcade) show "no data" over a readable empty axis.
  - Dark scheme: design purple and code blue apart; claude-opus-5-5 blue and unrecorded grey apart and visible on the dark background.
  - The problems note: "2 files could not be read: pickman/.tracker/issues/done/f0001/spend.md does not parse: row 3; history: map line 12 unreadable" on one muted line above the columns, columns unchanged.
  - Not observed: hover, keyboard, and an interactive window (AC4's node specs cover them).

Lesson candidates (for the lead to harvest; I write no lesson file):
- zz-review: when a source pin has been fixed twice for the same rule, the third review asks whether the rule is behaviour a spy or fixture can see (a call through a module table, a list handed to a shared function) before asking for one more forbidden spelling. Check: can this pin be replaced by observing the call it protects?

Verdict: approve

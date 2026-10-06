# Review 002: R0028 (design mode)
Inputs: c8eab73 (prep-board-graphs): `tracker/rafts/R0028/{R0028.md,check.sh,design-review-001.md,design-refute-001.md}`, `tracker/issues/c0073/{c0073.md,check.sh,acceptance/*.spec.luau}`, `scripts/tracker/board.{luau,html}`, `scripts/tracker/store.luau`, `tests/acceptance/c0042/{page,smoke,model,cli}.spec.luau`, `tests/tooling/board.spec.luau`, `tests/tooling/repo-fence.spec.luau`, the testing skill.
Dropped from design-review-001: F4's driven DOM harness. The refutation holds: the switching is a few lines of attribute toggling, its initial state is now Checked, and JC2/OC1 judge the rest. Every other review-001 finding is fixed in the documents and specs. I checked these and they hold:
- the nice-tick assertion (mantissa and step compared with a 1e-9 tolerance, so steps like 0.2 work);
- the thinning formula (n = 32 gives gaps 4/5);
- the hbars case;
- the token patterns against `board.html:8-11` (`:root { … }`, then `@media (prefers-color-scheme: dark) {\n  :root { … }`: both match);
- the busy fixture (ids pass `store.isIssueId`, the spend rows match the real `spend.md` header, today becomes 2025-12-27, and its history is nil because git fails in `.cache`);
- `{{STATS}}` (no c0042 spec pins the template; `render`'s two-placeholder check is in the touched `board.luau`);
- the `ser-` prefix (`board.html` uses `.s-done`/`.s-active`);
- RC1 (no banned name in the acceptance specs).

### F1 [high] The ratio-chart assertion can never pass: `ratios-count` goes into a Lua pattern unescaped
Where: `board-stats.spec.luau:151`, `string.match(section, `data%-chart="{v}/{r}".-</svg>`)` with `r` in `{ "ratios-count", "ratios-time" }`.
Evidence: in a pattern, `s-` means "zero or more `s`, lazily", so `ratios-count` matches `ratiocount` or `ratioscount`, but never the text `ratios-count` (the `-` is never consumed). I ran it in Lune on `<svg class="chart" data-chart="month/ratios-count" …><path class="line ser-defect"/></svg>`, and `string.match` returns `nil`. So `svg` is `""` for all six ratio charts, the `ser-defect`/`ser-chore` assertion fails, and AC10 is red for every implementation. The executor can't edit the spec, so this is an escalation on the first run.
Critique: the tempting fix is to escape only this one spot (`%-`). That works, but any later interpolated id that contains a hyphen hits the same trap.
Consequences: none beyond the spec edit.
Recommendation: cut the SVG with plain finds: `local a = string.find(section, `data-chart="{id}"`, 1, true)`, then `local b = string.find(section, "</svg>", a, true)`, then `string.sub(section, a, b)`. Assert that `a` is non-nil first, so a missing chart reports as missing. Do the same anywhere else an id is interpolated into a pattern.

### F2 [high] With no history, every `ratios-count` chart is "Empty", and the Design gives an empty chart no legend, so the ratio-series check fails a literal implementation (after F1)
Where: c0073 Design, "Empty" ("all values nil or zero, or no labels, gives the axis frame and `<text class=\"empty\">no data</text>`"), "Legend"; `board-stats :: the page has every chart…` run on `m`, the no-history tree.
Evidence: in `m`, `history = false`, so `closed` is 0 in every bucket. `defectCount` and `choreCount` are then nil everywhere (both denominators are closed counts), so `month|quarter|year/ratios-count` each have all-nil values. They are Empty charts: no path and no point. The only way `ser-defect` and `ser-chore` can appear in them is through legend swatches, and the Design never says that an Empty chart keeps its legend. The natural reading is "frame plus `no data`", with an early return. That implementation fails the case three times. `chart :: no data draws an empty frame` uses a single series, so it doesn't settle the question.
Critique: the tempting fix is to give the fixture history, which pulls a git fixture into a no-history spec. Or the executor reads the spec and "just adds the legend". Both leave the rule unwritten.
Consequences: an empty chart with a legend has to place `no data` so that it doesn't collide with the legend (JC2). The single-series rule stays the same: no legend, the title names it.
Recommendation: state it in Design "Empty" and "Legend": "the legend depends only on the series, so an empty chart with 2 or more distinct keys still has its legend". Add to `chart :: no data draws an empty frame` an all-nil `lines` chart with `defect` and `chore` series. Assert 0 marks, `no data`, and a `<g class="legend"` holding `swatch ser-defect` and `swatch ser-chore`. Add a Rules row: "an empty chart keeps its legend | chart :: no data… | legend dropped when empty | reasoned".

### F3 [medium] `board-stats` reads page shapes the Design doesn't state: the `<svg>` as the figure's first child, and no nested `<section>`
Where: `board-stats.spec.luau:121` (`'<section id="stats".-</section>'`, lazy), `:126` (`<figure class="chart%-fig"[^>]*>)%s*<svg class="chart" data%-chart=`), and `:185`; c0073 Design "Placement".
Evidence:
- JC2 requires that "every chart has a title". `<svg><title>` is only a tooltip, so an executor who wants a visible title will reach for `<figure><figcaption>…</figcaption><svg …>`, the textbook pattern. Every figure then fails the gmatch, and all 67 `figures[id] ~= nil` assertions fail.
- Wrapping each view's charts, or the tables, in a `<section>` cuts the stats match at the first inner `</section>`. The figures and control ids after it go missing.
- The Design states "no nested `<div>`" for `stats-tables` and "no nested `<g>`" for the legend, but neither of these two shapes.
- The ratio figures' and the durations figure's `data-type` value is also unstated (the Design only says they show "for every type"). The spec doesn't check it, but the script and JC2 depend on it.
Critique: the executor can recover by reading the spec, but that is reverse-engineering, which the documents should make unnecessary.
Consequences: a visible title then has to live inside the SVG, or in a `<figcaption>` after the `<svg>`. That changes F1's byte budget by a few bytes per chart.
Recommendation: add to "Placement":
- "the `<svg class=\"chart\" data-chart=…>` is the figure's first child; a visible caption, if any, follows it";
- "`<section id=\"stats\">` contains no other `<section>`";
- name the ratio and durations figures' `data-type` (for example `any`, matched by every type filter), so the eight-visible rule and the script agree.

### F4 [low] "Tooltips show values to one decimal" contradicts the spec's `2 issues` and `3 days`
Where: c0073 Design "Deterministic"; `chart.spec.luau:64,65,259`.
Evidence: `string.format("%.1f")`, the obvious reading of "to one decimal", yields `Net, a: 2.0 issues`, but the spec expects `Net, a: 2 issues` and `Feature, new: 3 days (n=2)`, alongside `1.5`.
Recommendation: write "at most one decimal, with a trailing `.0` dropped", for tooltip values and tick labels alike.

### F5 [low] Nice ticks below a step of 0.1 break the "no two-decimal literal" rule on real durations
Where: Design "Axis" and "Deterministic"; the `durations` chart.
Evidence: a durations chart whose largest mean is under about 0.25 days (spells of a few hours) gets a {1, 2, 5}×10ⁿ step of 0.05 or less, so it prints `0.05`. That breaks the stated rule. No spec covers it, so this is a latent contradiction rather than a red gate.
Recommendation: state a minimum step of 0.1, so the axis becomes `0, 0.1, 0.2` and still has at least 3 ticks.

### F6 [low] E3 still tells the executor to validate the removed `count` and `time` tokens
Where: c0073 "Unknowns & experiments", E3: "The executor re-runs it for the full set used (adding net, count and time)".
Recommendation: drop "count and time". E3b already states the set (four keys, on the page's surfaces).

Verdict: changes

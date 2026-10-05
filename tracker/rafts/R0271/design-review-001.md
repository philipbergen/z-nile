# Review 001: R0271 (design mode)
Inputs: a0750a3 (prep-board-graphs): `tracker/rafts/R0271/{R0271.md,check.sh}`, `tracker/issues/c0790/{c0790.md,check.sh,acceptance/*.spec.luau}`, `scripts/tracker/board.{luau,html}`, `tests/acceptance/c0400/*`, `tests/acceptance/c0460/*`, `tests/acceptance/c0550/open.spec.luau`, `tests/tooling/board.spec.luau`, `tests/tooling/repo-fence.spec.luau`, the dataviz references (`marks-and-anatomy.md`, `palette.md`, `anti-patterns.md`). R0250 rounds 6–9 were not reopened: the statistics, history and land points stand.

### F1 [high] AC10's 1.5 MB cap fails for a correct implementation today: the real page is already 1,540,060 bytes before any statistics
Where: c0790 AC10, `board-stats.spec` "the real tracker's page stays under 1.5 MB"; R0271 Risks ("Page weight"); c0790 Scalability ("a few tens of KB").
Evidence: `scripts/tracker.sh board -O --out <scratch>/board.html` on this worktree writes 1,540,060 bytes. The cap is `1.5 * 1024 * 1024` = 1,572,864, so 32,804 bytes are left. The embedded `board-data` JSON alone is 1,478,047 bytes, because the page carries every item document, so it grows with each raft whatever this issue does. An estimate from the real tracker (8 active days since 2026-09-28; created dates and spend rows per type; 133 bytes for a rect with its `<title>`; about 1.6 KB of frame per chart for ticks, grid, x labels, legend and root) gives about 140 KB of SVG for the 67 charts today. A fully active year (32 month buckets, 3 types, mirror charts with 6 series) gives about 380 KB. Add the stats rows in the JSON, roughly 25 KB. The page lands at about 1.7 MB now. A correct implementation fails AC10, and an empty Stats section would fail it within days anyway.
Critique: the tempting fix is to raise the cap to 2 or 3 MB. That still measures document bodies, not this issue's cost, so it stays a time bomb on the real tracker. A cap that passes today breaks some later raft that never touched the board.
Consequences: a budget for the Stats part alone needs a boundary the spec can cut on, and a worst-case input that doesn't depend on how busy the real tracker happens to be. A dense fixture tree costs a little spec time. It also makes the client-side fallback in the Risks a decision to take now, not an escalation.
Recommendation: replace the whole-page cap with a Stats budget:
- (a) Markup rule: the charts and tables sit inside `<section id="stats" …>…</section>`, with no nested `<section>`.
- (b) New case `board-stats :: the Stats section of a fully active year stays under 400 KB`. Write a `.cache/c0790-board-dense` tree in which every type has an item created, and a spend row, on each of the 366 days up to a fixed today (that's 1,098 issues; or 3 issues with spend rows on every day, plus created dates spread so every bucket has openings). Measure `#` of the substring from `<section id="stats"` to its `</section>`.
- (c) Keep a real-tracker case, but have it measure the Stats section, not the page.
- (d) Update R0271 Risks and c0790 Scalability with the measured numbers.
- (e) To stay inside the budget, the Design should ask for integer coordinates (see F6) and short tooltips. If (b) can't be met, decide now to build the 60 bucket charts client-side from the embedded rows, keeping only the frame markup in Lune.

### F2 [high] The ratio charts colour their two lines by measure, so both lines in a chart get the same colour
Where: c0790 Design, "Charts on the page": "`v/ratios-count` and `v/ratios-time`: `lines`, defect % and chore % (keys `count` and `time` per measure…)"; "Color" (`--series-count`/`--series-time`, slots 7 and 6).
Evidence: `v/ratios-count` holds two series, defect % and chore %, both measured by count. Both therefore carry key `count` and class `s-count`, so they get the same stroke and the same marker colour, and the legend shows two identical swatches. The same happens in `v/ratios-time` with `s-time`. That breaks the dataviz rule the Design itself cites ("color by job … a legend for 2 or more series"), and JC2's "a type keeps its color". The alternative reading (defect % keyed `count`, chore % keyed `time`) would colour series by an unrelated measure. No spec checks which keys a ratio chart uses.
Critique: the tempting fix, "use count/time but split the charts per ratio", changes the `data-chart` ids that `board-stats.spec` pins (`v/ratios-count`, `v/ratios-time`).
Consequences: keying the series by entity puts chore % in aqua, whose light contrast is 2.74:1 (E3's WARN), on a thin 2 px line, so the markers and the Table view must carry it. `--series-count` and `--series-time` go away, and E3's re-run covers six fewer tokens.
Recommendation: keep both chart ids, and key the series by entity: `defect` (defect %) and `chore` (chore %) in both charts. The chart title names the measure ("Defect and chore share, by count"). Remove `count` and `time` from the key list and the CSS. Add to `board-stats :: the page has every chart…`: cut out each ratio SVG (from its `data-chart="v/ratios-count"` to the next `</svg>`), and assert it contains `line s-defect` and `line s-chore`. Add a Rules row: "ratio lines are coloured by type | board-stats :: every chart | both lines keyed by measure".

### F3 [medium] Hiding an `<svg>` with `hidden` does nothing in browsers, but the Design says the page script "only toggles `hidden`" on the charts
Where: c0790 Design, "Charts on the page" ("The view switch and the type filter show and hide them. The page script only toggles `hidden`").
Evidence:
- `hidden` is an `HTMLElement` IDL attribute. `SVGSVGElement` doesn't have it, so `svg.hidden = true` just sets an expando property.
- The UA rule `[hidden] { display: none }` is in the HTML namespace's stylesheet, so a `hidden` attribute on an `<svg>` doesn't hide it unless the page's own CSS says so.
An implementation that follows the sentence literally shows all 67 charts at once. No spec can see this, because the specs read the markup, and OC1 is the only check.
Critique: the tempting fix is CSS `svg[hidden]{display:none}` plus `setAttribute`. It works, but it ties visibility to SVG attribute handling and leaves each chart's view and type implicit in its id string.
Consequences: a wrapper element adds a little markup to every chart (F1's budget), and gives the script and the specs a stable selector.
Recommendation: put each chart in an HTML wrapper, `<figure class="chart-box" data-view="month|quarter|year|all" data-type="all|feature|defect|chore|any">`, holding the `<svg>`, and toggle `hidden` on the figure. Add to `board-stats`: every `<svg class="chart"` is directly inside such a figure, and in the rendered page exactly the month/all figures (5 bucket charts, the 2 month ratio charts and `durations`, so 8) lack `hidden`. Add a Rules row.

### F4 [medium] The Stats interactions and the Table view have no Checked criterion, though measurable proxies exist and E3's pass relies on the Table
Where: c0790 Design ("A **Table** toggle shows the numbers … as the accessible view"; the view switch and type filter); E3 ("aqua's contrast is 2.74:1 … The legend, tooltips and the Table toggle provide them"); OC1; AC6/AC10; Regression guard.
Evidence: no case asserts that a table exists, what its columns are, or that the view switch or type filter changes what is visible. Only `stats-toggle` and `stats` are named ids. An implementation with no Table toggle and dead switches passes `check.sh`, and E3's WARN is then unanswered. `tests/tooling/board.spec.luau` holds a second fake DOM (`getElementById: i => els[i] || null`, `querySelector: () => null`, no `querySelectorAll`) that the Regression guard doesn't name, beside c0400's `smoke.spec`. A page script that calls `document.querySelectorAll("[data-chart]")` before its `if (!el) return` guard throws in both harnesses.
Critique: the tempting fix is "JC1 covers it". Visibility and table content are deterministic, so by the testing skill they belong in Checked.
Consequences: a driven test needs a stub richer than c0400's. That stub must not be the promoted one, which can't change, so the page script has to keep to a DOM subset that both the old stubs and the new one support.
Recommendation:
- Name the ids: `stats-view` (buttons with `data-view`), `stats-type` (buttons with `data-type`), `stats-table-toggle`, `stats-tables`.
- Rule: the script touches the new elements only through `$()`, and through `querySelectorAll` on the element `$("stats")` returns, after the null guard. Never through `document.querySelectorAll`.
- Add `board-stats :: the Table view has one table per view, the periods and the time in state, with units in the headers`. It checks, in the static HTML or after rendering, the header texts `minutes`, `+lines`, `−lines`, `days`, `%`.
- Add `board-stats :: switching view and type shows only that view's charts`: a node harness under `.cache/c0790-board-dom` whose stub implements `querySelectorAll`, `hidden`, `dataset` and `click` on the stats subtree. It clicks Quarter, then Defect, and asserts which figures (F3) are hidden.
- Name `tests/tooling/board.spec.luau`'s harness in the Regression guard.
- Move the switching part of OC1 to Checked.

### F5 [medium] `chart.spec` parses markup shapes that the Markup shape section doesn't state, so a correct implementation can fail it
Where: c0790 Design "Markup shape", "Marks", "Legend"; `chart.spec.luau:122` (legend), `:100` (`<circle` count), `:10` (`marks()`).
Evidence:
- **Legend**: `string.match(two, '<g class="legend".-</g>')` is lazy, so it stops at the first `</g>`. A legend built as one `<g>` per entry, which is the common form (`<g class="legend"><g>swatch Feature</g><g>swatch Chore</g></g>`), yields only the Feature entry, and the `Chore` assertion fails.
- **Line markers**: `count(svg, "<circle")` must be 3. The dataviz "2px surface ring" drawn as a ring circle plus a dot circle gives 6, and a circle used as a legend swatch adds more.
- **Bar ends**: the Design asks for "4 px rounded data ends, anchored to the baseline", and dataviz says "square at the baseline". `<rect rx>` rounds all four corners, so it can't do that, and a `<path>` mark isn't found by `marks()`, which only reads `<rect class="mark">` with `y` and `height`. The Design asks for two things that conflict.
Critique: the executor can't edit the spec, so they will reverse-engineer it, or escalate in the middle of execution.
Consequences: each shape rule also limits the visual design, so the rounded ends need an explicit decision.
Recommendation: add to "Markup shape":
- the legend's swatches and labels are direct children of `<g class="legend">`, with no nested `<g>`;
- a `lines` chart has exactly one `<circle class="point s-<key>">` per non-nil value, and no other `<circle>` (the ring is a CSS stroke on the same circle; legend swatches are `<rect>`);
- marks are square-ended `<rect>` (no `rx`), and the rounded data end is dropped, recorded as a deliberate deviation in JC2's rubric. Or, if it's kept, an extra `<path class="cap">` that isn't a mark (more bytes, see F1).

Add a Rules row for each.

### F6 [medium] The deterministic-decimals assertion bans ordinary SVG literals that the Design never forbids
Where: `chart.spec.luau:163` (`string.find(draw(), "%d%.%d%d") == nil`); Design "Deterministic" ("numbers formatted to at most 1 decimal").
Evidence: the pattern scans the whole SVG, not the data numbers. The viewBox (`0 0 640 200`), integer font sizes, ISO dates and `W40` are safe. But these common, legitimate idioms match:
- `dy="0.35em"` (vertical text centring);
- `stroke-opacity="0.15"` or `opacity="0.12"` (recessive grid lines);
- `font-size="0.75em"`.

A correct implementation that uses any of them fails AC8. The case also exercises only `stacked`, so the `d` coordinates of `lines` paths, the mirror geometry and `hbars` widths can still print `213.33333333333334` and pass. Separately, the stats durations have two decimals while chart tooltips round to one, so the Table and the tooltip disagree, and nothing says which wins.
Critique: the tempting fix is to loosen the pattern to coordinates only. The stricter rule is fine and helps F1 too; it just has to be written down.
Consequences: integer or one-decimal coordinates need a rounding rule that keeps stacked segments adjacent (round the cumulative edges, not each height), or the 2 px gap varies by ±0.1.
Recommendation: state in "Markup shape": "no numeric literal anywhere in a chart has more than one decimal; text is centred with `dominant-baseline`, and opacities live in the page CSS". Coordinates are rounded to 1 decimal from cumulative edges. Extend the determinism case with a `lines` chart (values `{ 1/3, nil, 2/3 }`) and a `mirror` chart, each asserting the same pattern. Say that tooltips show durations to one decimal and the Table shows two.

### F7 [medium] Nice-number ticks, the negative bottom tick and x-label thinning have no Rules row and no case that can fail
Where: Design "Axis" and "X labels"; `chart.spec :: one axis whose top tick covers the largest total`; Rules and mutants table.
Evidence:
- "one axis" only asserts `13 <= top <= 20`. Ticks `0, 3.3, 6.5, 9.8, 13` (top equals the total, not nice) pass.
- The negative-bars case checks only where the rect sits. A domain clamped at 0, where −3 hangs below the frame with no tick under 0, passes.
- Mirror's below series can likewise go below the frame unticked.
- "At most 8 x labels, evenly thinned" has no row and no case. A month chart with 32 overlapping date labels passes and is left to JC2, although it is a countable proxy.
- No class is defined for x labels.
Critique: these are the rules a hurried implementation gets wrong first, and they are measurable.
Consequences: the mirror axis needs a decision on how a below-the-baseline tick is labelled (signed, `−20`, or absolute, `20`). The x-label class also counts toward F5's shape rules.
Recommendation:
- In "one axis", assert that the tick values are `0, s, 2s, …` with `s` in {1, 2, 5}×10ⁿ, and that there are 3 to 6 of them.
- In the negative-bars case, assert that the smallest tick is at most −3.
- In the mirror case, assert that the smallest tick is at most −2, labelled signed (decide and state it; a typographic `−` would break the `[%-%d%.]+` parse, so use ASCII `-`).
- Add `<text class="x" …>label</text>` to the Markup shape, and a case with 32 labels: at most 8 `class="x"` texts, the first and last labels present, and evenly spaced indices.
- Add a Rules row for each.

### F8 [medium] `hbars` (the durations chart) has no spec case, and its contract can't carry the `n` the Design puts in its tooltip
Where: Design "Kinds" (`hbars`), "Charts on the page" ("`durations`: `hbars` … `n` in each tooltip"); `Series = { key, label, values: { number? } }`; `chart.spec` (no hbars case); Rules table.
Evidence: `Series` and `Options` have no field for a per-value count, and the tooltip format is fixed as `<label>, <bucket label>: <value> <unit>`, so `chart.svg` can't produce "n". The markup for a horizontal chart isn't defined either: marks grow along x (`x`/`width`), and the baseline is vertical, but the shape rule pins `<line class="baseline" … y1=…>`. In `board-stats` the fixture has no history, so `durations` is empty. A missing, empty or vertical `hbars` implementation therefore passes every check.
Critique: the tempting fix is to fold `n` into the label ("Feature (n=4)"). The legend then shows a count for one state only, which is wrong for the other states.
Consequences: a new optional `Series` field has to be ignored by the other kinds, and must not break determinism.
Recommendation:
- Add `notes: { string? }?` to `Series`. The tooltip becomes `<label>, <bucket>: <value> <unit> (<note>)` when a note is present, and the board passes `n=<n>`.
- Define hbars markup: `<rect class="mark s-<key>" x= width=>`, and a vertical `<line class="baseline" x1=…>`.
- Add `chart :: hbars draws one horizontal bar per non-nil mean, with n in its tooltip`. Use 2 labels × 2 series, one nil. Expect 3 marks, widths proportional to the values, every mark's `x` ≥ the baseline's `x1`, and a tooltip `Feature, active: 1.5 days (n=4)`.
- Add a Rules row.

### F9 [medium] The dark-mode CSS assertion only reads the page's first dark media block, which already exists, and checks just one token
Where: `board-stats.spec.luau:132-135`; `scripts/tracker/board.html:9-11`; Design "Color"; AC10.
Evidence:
- `string.match(html, "@media %(prefers%-color%-scheme: dark%).-\n}")` takes the first dark block. That is the existing one at `board.html:9`. A correct implementation that follows the dataviz palette pattern, a separate `@media … { :root:where(:not([data-theme="light"])) {…} }`, puts `--series-feature` in the second block, and the case fails.
- `[data-theme="dark"]` is required, but nothing on the page sets `data-theme`, and the page's own tokens (`--bg`, `--fg`, …) have no such scope, so it is dead CSS.
- Only `--series-feature` is checked. A dark block that copies the light hex values, or leaves out defect, chore or net, passes.
- So does a page with no `.s-feature { fill: var(--series-feature) }` rule, where every mark renders black.
Critique: the tempting fix is "add it to the existing block", which is fine, but it isn't written anywhere, so the spec quietly sets the CSS structure.
Consequences: if the `data-theme` scope stays, say it is for a future toggle, and give the base tokens the same scope, or the two halves disagree.
Recommendation:
- In the Design, say the series tokens go in the existing `:root` rule and the existing dark media block, plus `:root[data-theme="dark"]`, the last for every token or for none.
- Strengthen the case. For each key in `feature, defect, chore, net`, the light value differs from the dark value. A rule maps `.s-<key>` to `var(--series-<key>)` for both `fill` and `stroke`.

### F10 [low] The mirror legend repeats colours
Where: Design "Legend", "Charts on the page" (`v/t/lines`: `mirror`, added above and removed below, per type).
Evidence: for `all`, mirror has 3 series above and 3 below with the same keys. "One swatch and label per series" gives 6 entries in 3 colours. For a single type, it gives 2 same-coloured entries ("Added", "Removed").
Recommendation: the mirror legend lists only `series` (the types). The title or a y-axis caption says "added above, removed below". Add a legend assertion to the mirror case: exactly one entry per distinct key.

### F11 [low] The colour check misses other inline-colour forms
Where: `chart.spec :: colors are classes, never inline`.
Evidence: it only bans `fill="#`, `stroke="#` and `style=`. `fill="rgb(42,120,214)"`, `fill="steelblue"` and `fill="var(--series-feature)"` all pass.
Recommendation: assert that every `fill="…"` and `stroke="…"` value is `none` or `currentColor`.

### F12 [low] E3 was validated on surfaces the page doesn't use, and the raft doc's dependency text is stale
Where: c0790 E3 (light `#fcfcfb`, dark `#1a1a19`); `board.html:8,10` (`--bg: #fff`, `#15171a`); R0271 "Order & dependencies" and Risks ("R0250 itself waits for R0210", "R0210's spec rules apply").
Evidence: contrast and ΔE were computed against the palette's own surfaces, not the page's. R0210 is in `tracker/rafts/done/` (merged in #49), and `tests/tooling/repo-fence.spec.luau` with `local NAMES` is on main, so RC1 runs today.
Recommendation: the executor re-runs the validator with `--surface #ffffff` and `#15171a` (or the board adopts the palette surfaces inside the Stats section). Rewrite the R0210 lines as "R0210 is done; its spec rules apply".

### F13 [low] Where the SVG markup goes in the template is unstated
Where: Design "Board"; `board.luau:361-375` (`render` takes exactly `{{MARKED}}` then `{{DATA}}`).
Evidence: the 67 SVGs have to be raw markup. Inside `board-data`, `"` becomes `\"` and `<` becomes `<`, so `data-chart="…"` would never match. c0400 `page.spec` also requires `board-data` to decode exactly to the model, which rules out stashing SVG in the model. The Design names no third placeholder, and `render` errors on any other layout.
Recommendation: name a `{{STATS}}` placeholder after `{{DATA}}`. `render` builds the section from `m.stats` with `chart.svg` and assembles the pieces in order without `gsub`, as it does now. Extend its error message to name all three placeholders.

Verdict: changes

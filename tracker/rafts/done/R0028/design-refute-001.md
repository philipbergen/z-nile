# Refute 001: R0028 design review 001

- F1: fixed: AC10 drops the whole-page cap (the embedded documents already make about 1.5 MB). It caps the `<section id="stats">` markup at 450 KB on a generated busy year (240 issues with spend, under `.cache`), in a new board-stats case.
- F2: fixed: the ratio lines are keyed `defect` and `chore`, taking their types' colors, and `--series-count/time` are gone. The page case checks that each ratio SVG holds both classes.
- F3: fixed: each SVG is wrapped in `<figure class="chart-fig" data-view data-type>`, and `hidden` is toggled on the figure. The page case checks the attributes, and that exactly the eight month/all figures start visible.
- F4: fixed in part:
  - The control ids are named (`stats-view`, `stats-type`, `stats-table-toggle`, `stats-tables`), along with the script rule: new elements only through `$("stats")` after its guard, and `querySelectorAll` on it, never on `document`. `tests/tooling/board.spec` and c0042's smoke stub are named in the Regression guard.
  - A Table case checks the tables and the units in their headers.
  - refuted: a node DOM harness for the switching itself. The switching is a few lines that toggle `hidden` by two data attributes. Its initial state is Checked (AC10); the switching stays JC2/OC1. A new harness under `.cache` would cost more than the logic it guards.
- F5: fixed: the Markup shape now states: legend children are direct (no nested `<g>`); exactly one `<circle class="point ser-<key>">` per non-nil value and no other circles; marks are square-ended rects. The rounded data end is dropped deliberately, and JC2 accepts it. Rules rows were added.
- F6: fixed: no numeric literal in a chart has more than one decimal. Coordinates are rounded from cumulative edges, text is centered with `dominant-baseline`, and opacities live in CSS. The determinism case now also covers `lines` (thirds) and `mirror`. Tooltips round to 1 decimal, and the Table shows 2.
- F7: fixed: the axis case asserts ticks `0, s, 2s, …` with `s` in {1, 2, 5}×10ⁿ, 3 to 6 of them. The negative and mirror cases assert a signed tick at or below the minimum (an ASCII `-`). x labels are `<text class="x">`, thinned to `round(1 + k·(n−1)/7)`, and a 32-label case checks at most 8, first and last kept, gaps differing by at most 1. Rules rows were added.
- F8: fixed: `Series.notes` was added (shown as ` (<note>)` in the tooltip) and the hbars markup is defined: rects growing right from a vertical baseline. An hbars case checks 3 marks, the tooltips with `n=`, `x` ≥ the baseline and proportional widths.
- F9: fixed: the tokens go in the existing `:root` and dark media block. There is no `data-theme` scope, since the page has no toggle. The case checks each key (feature, defect, chore, net): light ≠ dark, and a `.ser-<key>` rule using `var(--ser-<key>)`.
- F10: fixed: a mirror's legend lists each key once, and the legend case checks it.
- F11: fixed: the chart markup has no `fill=`, `stroke=` or `style=` at all, and the case checks for those attributes, so `rgb()`, named colors and `var()` are excluded too.
- F12: fixed: E3b re-validates on the page's surfaces (`#ffffff`, `#15171a`): the same pass, with aqua's WARN at 2.82:1. R0028 no longer says it waits on R0021 (done, #49).
- F13: fixed: the Stats markup is raw HTML, filled through a third placeholder `{{STATS}}` inside `<section id="stats">`, not through the escaped JSON.
- Not in the review: the page already uses `.s-done`/`.s-active` for status badges, so chart series classes use the `ser-` prefix.

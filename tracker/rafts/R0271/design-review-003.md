# Review 003: R0271 (design mode)
Inputs: e0de63b (prep-board-graphs): `tracker/rafts/R0271/{design-review-002.md,design-refute-002.md}`, `git diff c8eab73 e0de63b -- tracker/issues/c0790`, `tracker/issues/c0790/{c0790.md,check.sh,acceptance/board-stats.spec.luau,acceptance/chart.spec.luau}`.
Dropped from design-review-002: F1–F6, all fixed and checked:
- F1: the ratio SVG is cut with plain `string.find` calls (`board-stats.spec.luau:151-153`), so the hyphen in `ratios-count` is no longer a pattern character. The `or 1` fallback only runs when `figures[id] ~= nil` has already failed, so it can't produce a false pass.
- F2: Design "Empty" now keeps the legend for two or more keys. `chart :: no data draws an empty frame` adds a two-series all-nil `lines` chart and asserts `no data` plus `ser-defect`/`ser-chore` inside `<g class="legend">`. The pattern `'<g class="legend".-</g>'` has no literal hyphen, and the legend has no nested `<g>`, so it cuts correctly. `{ nil, nil }` is an empty table in Luau, and any implementation that indexes by label or uses `ipairs` treats it as all-nil. In the no-history fixture `m`, `durations` (three type series) is also empty and keeps its legend under the same rule, which is consistent.
- F3: Placement now states that the `<svg>` is the figure's first child with any `<figcaption>` after it, the ratio figures' `data-type="any"`, `durations` as `data-view="all" data-type="any"`, and no nested `<section>`. These agree with the spec's gmatch and lazy section cut, and with the eight-visible rule.
- F4, F5: tooltips use at most one decimal with a trailing `.0` dropped, which matches `2 issues`/`1.5`. A minimum tick step of 0.1 still leaves room for 3 or more ticks, because the top tick may exceed the largest value.
- F6: E3 now names the three types plus net's gray.

Nothing new blocks delivery. One bookkeeping gap remains:

### F1 [low] The Rules table has no row for "an empty chart keeps its legend"
Where: c0790 "Rules and mutants"; review 002 F2 asked for the row.
Evidence: the rule is in Design "Empty", and the spec case `chart :: no data draws an empty frame` kills the mutant "legend dropped when empty". The table still only has "a legend iff 2 or more series; one entry per key", which names `chart :: a legend…`, not the empty case.
Critique: this doesn't affect what gets delivered. It only makes the table incomplete for the code reviewer's audit.
Consequences: none.
Recommendation: add `| an empty chart with 2 or more keys keeps its legend | chart :: no data draws an empty frame | legend dropped by an early return when empty | reasoned |`.

Verdict: approve

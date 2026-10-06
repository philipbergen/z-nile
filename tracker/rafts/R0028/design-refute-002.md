# Refute 002: R0028 design review 002

- F1: fixed: the ratio SVG is cut out with plain `string.find` calls (`data-chart="<v>/<r>"`, then the next `</svg>`), so the hyphen in `ratios-count` no longer acts as a pattern character.
- F2: fixed: an empty chart with two or more keys keeps its legend. The Design says so, and chart.spec's empty case gained a two-series all-nil `lines` chart that must show `no data` and both legend entries.
- F3: fixed: the `<svg>` is each figure's first child (a `<figcaption>`, if any, comes after it). The ratio figures have `data-type="any"`, `durations` has `data-view="all" data-type="any"`, and the Stats section holds no nested `<section>`.
- F4: fixed: tooltips show at most one decimal, with a trailing `.0` dropped.
- F5: fixed: the tick step is at least 0.1.
- F6: fixed: E3 now names the full set as the three types plus net's gray. `count`/`time` are gone.

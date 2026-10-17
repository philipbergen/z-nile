# Review 002: R0028 (code mode)
Inputs: c7ee03521ceef73e16ff8ae358d951317f7f0b71. Fix delta `6909478..HEAD` (021813d plus this refute). Whole diff against origin/main, R0028.md, c0073.md, both check.sh files, chart/stats/board and board.html. `scripts/check.sh --full`: GATE PASSED, 1531 passed, 0 failed, selene 0 errors, 0 warnings. `scripts/tracker.sh check c0073`: 10/10. Sequestration still lists only the type-annotation hunks in `chart.spec.luau` and `board-stats.spec.luau`.
Dropped from review-001: F1, F2, F3, F4

## Judged criteria
- JC1: pass. The Periods table lists opened and closed per type for this week, this month and this year, with unit headers. This week is 0 opened and 0 closed on every row, 58.2 minutes, and a blank defect % because nothing closed (the cell is empty, not `%`). This month is 2204.1 minutes with defect % `0%` and defect time % `0%`. This year is 2411 minutes and defect % `0%`. No binary tails. A first-time viewer can read the counts and the defect ratio. Column `n` on time in state is still the design's own abbreviation, not a failure.
- JC2: pass. Bucket charts have a title, a legend at two or more series, class colors that do not change with the filter, and one axis. Month x labels stay about 75 apart against a ~40-wide label, so they do not collide. Square bar ends are the allowed exception. hbars has no tick scale; its values are in the tooltips its own bullet requires. Line charts are a path plus one titled circle per non-nil point, including 0, and no bar marks. `.chart-fig[hidden] { display: none; }` beats `.chart-fig { display: inline-block }`. The page starts with 8 figures without `hidden` and 59 with it, and the view and type buttons only add or remove that attribute, so switching hides a chart.

Verdict: approve

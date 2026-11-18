---
title: Run the loop scan after adding a loop
when: build
tags: [loops, gate, watch-map]
check: Did this layer add or change a `while` or `repeat` loop in `z-nile/`, `scripts/` or `pickman/scripts/`, and if so did you run `lune run tests/run -- tests/meta/scanning-loops.spec.luau tests/acceptance/c0193/tree.spec.luau` from `z-nile/` before `./zn finish`?
---
The loop scan (zz-arch rule 9) reads every tooling file, but its two specs' watch files name only the scan's own libraries. An affected gate therefore does not select them for a layer that adds a loop to an engine file, and `./zn finish` and `./zn done` pass with the scan red. Only a full gate, or the next layer whose files happen to be in those watch files, shows it.

**Why:** f0399 (raft R0129, landed 2026-11-17 as da3de3462) added `while #lines > 0 and lines[#lines] == "" do` to `engine/guesses.luau` and `while #out < #issues do` to `engine/raftplan.luau`. Every `finish`, the code review, the final review and `done`'s affected gate passed. Main's full gate was then red in `meta/scanning-loops` and `c0193/tree`, and R0113's `finish` was refused for it (d0413). The second loop could also never return for a repeated id, which the scan's rule exists to make someone argue.

**How to apply:** After writing any `while` or `repeat` loop in the tooling, run the two scan specs by path. Prefer a numeric `for` with a fixed number of passes, which the scan proves by itself; list a loop in `tests/lib/loops.luau` only with the reason it ends. Until the watch files of the two specs name the trees they read, the affected gate is not the check for this rule.

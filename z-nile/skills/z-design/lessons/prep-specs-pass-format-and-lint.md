---
title: A prep's specs and experiments pass the gate's format and lint before the prep commit
when: design
tags: [stylua, selene, format, lint, sequestration, specs, experiments]
from: c0292 (lesson ticket, withdrawn 2026-11-16)
check: Did 'stylua --check' and 'selene' run clean over the issue's folder (acceptance/, experiments/) on the prep commit?
---
The full gate's format and lint stages read every `.luau` in each project's `.tracker/`, the issue's `acceptance/` and `experiments/` included, and fail on a diff, an error or a warning. Nothing a prep runs earlier does: not `tests/run`, `./zn check` or `./zn promote-check`, and the Claude Code edit hook (no other CLI runs it) sees only its editor's writes, not a shell command, a copy or a merge. They read no `.sh` and no `.luau.txt`. Under `./zn dispatch` the prep gate merges on CI, which runs no gate, so a failing folder reaches main (c0359).

**Why:** c0261's prep PR #259 reached its merge gate on 2026-11-09 with all 12 acceptance specs unformatted, invalid `'\{'` escapes in plain strings and an unused require; the gate failed at format and lint.

**How to apply:** from the repository root, after writing the specs (before the mutation check and the review), right before the prep commit, and again after any later change to a `.luau` in the folder: `d=$(./zn find <id>); stylua "$d"; stylua --check "$d" && selene --quiet "$d"`, until both exit 0 (selene exits 1 on a warning alone). Name the folder: `stylua .` skips `.tracker/` (zz-test/format-tracker-specs-by-path).

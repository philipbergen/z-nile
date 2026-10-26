---
title: Format sequestered specs from the checkout's top, where stylua finds its config
when: design
tags: [format, stylua, prep]
check: Was every edited spec formatted with stylua run from the checkout's top (or with its path from there), and does `stylua --check <item folder>` from the top pass before the prep commit?
---
stylua reads `stylua.toml` from the folder it runs in and its parents. Run inside an item's `acceptance/` folder of a worktree, it can miss the repository's settings (line width, wrapping), so the files it writes differ from what the gate's `stylua --check` expects, and the prep's gate fails at its first stage.

**Why:** c0141, c0139 and c0152's preps (2026-10-26): every round's spec edits were formatted with `stylua *.luau` from the acceptance folder; c0141's landing gate failed on `uses-module.spec.luau`'s wrapping.

**How to apply:** run `stylua z-nile/.tracker/issues/<id>/acceptance/` from the checkout's top, and `stylua --check` the item folder before committing.

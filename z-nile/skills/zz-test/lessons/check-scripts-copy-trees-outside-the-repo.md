---
title: A check script that runs a copy of the tree builds it outside the repository
when: both
tags: [check-sh, fixtures, safety, jail]
from: c0302 design review 001 F7
check: Does any script a check.sh runs execute, or write through, files at a fixed path under `.cache`, and does every early exit remove the copy?
---
A check.sh command runs outside the jail. A copy of the tree at a fixed name under `.cache` is writable by every jailed spec of a concurrent run in the same checkout, so a spec could swap a destination for a link, or edit the copy's runner before the script starts it. An early exit also leaves a full clone behind.

**Why:** c0302 design review 001 F7: `layer.sh` cloned the checkout into `z-nile/.cache/c0302-layer`, copied seven files into the clone and started its runner there; four early exits skipped the final removal.

**How to apply:** `hold=$(mktemp -d "${TMPDIR:-/tmp}/<id>-<name>.XXXXXX")`, `trap 'rm -rf "$hold"' EXIT`, and check that the copy is its own checkout before any git command names it (zz-test, Writers).

**Note (c0281 prep):** c0281's mutation driver made its copy with mktemp under the home's `.cache`, and an error between the copy and its removal left it behind; it moved to `$TMPDIR` with the removal after an `xpcall`. Ask: is the copy outside the repository even when its name is random, and does the removal run when the check stops on an error?

**Note** (c0178, 2026-11-24): code review 001 F4: `check.sh` wrote two spec-path lists through fixed names at the top of the real home's `.cache` (shell redirections follow a link swapped in there), and nothing removed them. Design review 005 F5: AC3 cloned the base tree to `<home>/.cache/c0178-check/base`, where the head's jailed suite could write it, then ran its runner unjailed, with no trap. The design had cited this very lesson as followed, for the clone only. Check: does every file a check writes, not only its clone, go into a `mktemp -d` folder outside the repository with a trap, and is the clone verified to be its own top-level checkout before git names it?

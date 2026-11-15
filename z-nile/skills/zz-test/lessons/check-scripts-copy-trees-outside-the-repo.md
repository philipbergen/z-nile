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

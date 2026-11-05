---
title: A check.sh path built from `./zn find` is relative to the project home
when: design
tags: [check-sh, paths, sequestration]
check: Does every path a check.sh builds from `./zn find` or `./zn members` output use it as it is (relative to the project home that ac.sh cds to, so `$PWD`), never prefixed with `$ZN_ROOT`, and was the check run before promotion as `./zn done` runs it?
---
`ac.sh` changes to the item's project home before any check runs, and `./zn find` prints paths from the folder it runs in. A path joined to `$ZN_ROOT` then names a folder at the repository root that does not exist; a fallback to the promoted `tests/acceptance/<id>` hides it until `./zn done`, which runs the raft's `check.sh` before it promotes anything.

**Why:** R0051's RC1, 2026-10-26: `F0110_SPECS="$ZN_ROOT/$F0110/acceptance"` failed at execution's Phase 3; the user approved a one-line fix of the sequestered file.

**How to apply:** use `$PWD/$(…zn find <id>)` (or the path as printed); run the raft's `check.sh` in prep with the specs still sequestered, the way `done` runs it.

---
title: Code that reads the process table degrades where `ps` cannot run, and its proof passes the fact in
when: both
tags: [jail, ps, specs, platform]
check: Does each engine path that runs `ps` (or any setuid tool) survive a refusal (`sh.run` raises when the spawn is denied), say what it does without the answer, and does a spec supply the answer another way?
---
The spec jail denies `ps` (`Operation not permitted`), and `sh.run` raises instead of returning not-ok.

**Why:** c0275 prep (2026-11-12): the first claim in a spec that started a background beater died in `ps` while finding the session. Wrapped in `pcall`, the beater is then bound by its time and worktree only, and the proof gives `--session <pid>` by flag.

**How to apply:** wrap the lookup, pin the fallback, and test the choice of the answer as a pure function over a table.

---
title: A spec that reads a source file is selected when that file changes
when: build
tags: [affected, selection, source-pins]
check: For each source file a spec reads as text, does `lune run z-nile/affected -- <that file>` list the spec?
---
The affected selector follows requires. A spec that reads a source with `fs.readFile` requires nothing it reads, so a change to that source never selects it, and `--affected` stays green while the pin is broken until a full run.

**Why:** R0056 code review 002 F1: `tests/place/main-walls.spec.luau` read `src/client/Main.client.luau` with `fs.readFile`; `lune run z-nile/affected -- pickman/src/client/Main.client.luau` listed 35 specs without it.

**How to apply:** read a game source through the built place (`place.load()`, which the selector picks for every src/ change), and strip its comments (and strings, where a call inside one would count) before matching. Check the result with `lune run z-nile/affected -- <file>`.

---
title: A spec that reads a source file is selected when that file changes
when: both
tags: [affected, selection, source-pins]
check: For each source file a spec reads as text or runs only through a probe or child process, does `lune run z-nile/affected -- <that file>` list the spec, given the watch `./zn finish` will write?
---
The affected selector follows requires. A spec that reads a source with `fs.readFile` requires nothing it reads, so a change to that source never selects it, and `--affected` stays green while the pin is broken until a full run.

**Why:** R0056 code review 002 F1: `tests/place/main-walls.spec.luau` read `src/client/Main.client.luau` with `fs.readFile`; `lune run z-nile/affected -- pickman/src/client/Main.client.luau` listed 35 specs without it.

**How to apply:** read a game source through the built place (`place.load()`, which the selector picks for every src/ change), and strip its comments (and strings, where a call inside one would count) before matching. Check the result with `lune run z-nile/affected -- <file>`.

**Note (R0102 review-001 F1):** the same hole opens when a spec reaches its subject only in a child process, or through a require split to dodge the require scans (a probe). The watch `./zn finish` writes is the layer's sources or, when the layer changes none, what the specs require, so it does not name that subject. c0302's maintip.spec, the only pin of `layergit.mainTip`'s refusal, watched `tests/lib/fixture.luau` and `t.luau`, and `lune run z-nile/affected -- z-nile/engine/layergit.luau` did not list it. In prep, on a prototype with the spec and that watch in the promoted layout, run the selector on the subject; the Design says which gate runs the spec otherwise. c0341 changes the derivation.

**Also:** d0297 design review 001 F4: a promoted case scanned `z-nile/check.sh`, `scripts/affected.luau` and the hooks as text to prove none passes a flag, but its ticket watch is written from the layer's own sources, so a change to `z-nile/check.sh` alone would not select it. The answer was a tooling spec with its own `<name>.watch.txt` naming those files, and a prototype run showing that each of them selects it.

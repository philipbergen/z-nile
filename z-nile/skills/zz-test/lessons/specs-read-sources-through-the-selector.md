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

**Also:** d0297 design review 001 F4: a promoted case scanned `z-nile/check.sh`, `z-nile/affected.luau` and the hooks as text to prove none passes a flag, but its ticket watch is written from the layer's own sources, so a change to `z-nile/check.sh` alone would not select it. The answer was a tooling spec with its own `<name>.watch.txt` naming those files, and a prototype run showing that each of them selects it.

**Note (R0109 review-001 F2):** a second instance. d0333's commit-land.spec is the one fixture that commits with `./zn commit` after a finish, and it reaches `main.luau`, `spend.luau` and `workread.luau` only through `./zn` child processes, so its finish-written watch names only `layergit.luau` and `trace.luau`; `lune run z-nile/affected --` those three files lists 226 specs and not this one (c0341).

**Note (f0209 design review 001 F3):** a spec that builds the real places with Rojo (deploy.spec, runtime.spec) reaches `portal/src` and `default.project.json` only through child processes, so its finish-written watch names `experience.json` and `structure.luau` alone. A `tests/inputs.tsv` row does not help: `z-nile/lib/context.luau` builds the selector's context with `inputs = {}` and nothing calls `sel.parseInputs` (f0209 E7, run on its prototype). Say in the Design which gates run such a spec for a source change (the full gate, cicd), and put the rule where the next designer reads it (the project's test skill).

**Note (R0117 code review 001 F2):** a reviewer recommended `tests/inputs.tsv` rows so that portal's acceptance specs are selected by the lower layers' and the arcade's sources they load. That mechanism does nothing (f0209 F3 above: `z-nile/lib/context.luau` builds the context with `inputs = {}`), and the ticket watch is finish-written inside the sequestered acceptance folder, so neither the executor nor the reviewer can add those paths. Before recommending a selection fix, run `lune run z-nile/affected -- <source>` on a prototype of the fix; a layer's specs that load another layer's or the library's sources are covered by the full gate at the merge and by the watch net, and the Design should say so.

**Note** (c0178 code review 001 F5, 2026-11-24): the diff added `trackerfix.luau` and `fxclone.luau` to the watch files of 116 specs that name them, but 16 watch files cover specs that build the same fixtures and name neither (`c0136`, `c0138`, `d0415`, `f0399`, `tooling/stack-land` and others), so `--affected` skipped 24 of 94 fixture specs, 18 of them fast. Check: `lune run z-nile/affected -- <the changed helper>` lists every spec that builds on it, found through its callers (such as `fakecli.new`), not only by a grep of the helper's name?

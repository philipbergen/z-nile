---
title: A fixture that runs the gate owns its HOME and ignores what the gate writes
when: both
tags: [fixtures, gate, tools]
check: Does a fixture that runs `check.sh` set its own HOME (so `$HOME/.rokit/bin` can't put the real tools before its stubs), run rokit's shims with the real HOME, ignore every file the gate writes (`sourcemap.json`, `.cache/`), copy what `engine.copy` leaves out (`z-nile/tests/run.luau`, `z-nile/tests/lib`), and reset every guard marker it inherits whose guard it tests (`PICKMAN_OPEN_GUARD=""`)?
---
`check.sh` puts `$HOME/.rokit/bin` first on PATH, so under the real HOME the real rojo and stylua shadow a fixture's stubs. A rokit shim also finds its tool through HOME, so under a fixture HOME the shimmed `lune` fails with `No such file or directory`. The gate itself writes files (the `rojo sourcemap` step writes `sourcemap.json` beside the project file). In a fixture that isn't ignoring them, those writes dirty the tree that the gate's own checks read. `engine.copy` copies the tooling but not `z-nile/tests`, so a fixture that runs specs has no runner.

**Why:** c0165 prep (2026-10-26). The prototype ran gate.spec, and every one of these failed in turn:
- the real rojo canonicalized a missing `default.project.json`;
- `specs.luau` couldn't resolve `./tests/lib/fence`;
- the content digest moved during the gate, so the whole-gate record was never written;
- and, once HOME was set, rokit's lune shim couldn't start under `./zn check`.

**How to apply:** give the fixture `HOME=<fixture>/home` with `.lune/.typedefs/<lune version>` made, and a `bin/lune` wrapper that runs the real `lune` with the real HOME. Put `sourcemap.json` (and every other gate output) in the fixture's `.gitignore`. Copy `z-nile/tests/run.luau` and `z-nile/tests/lib` after `engine.copy`. `c0120/gate-homes.spec` is the model.

A nested runner inherits the outer run's guard markers. With `PICKMAN_OPEN_GUARD` set, the fixture's runner skips its own browser guard, so a spec that tests that guard sees it never fire, and the real run around it fails instead (c0165 prep, round 1's prototype). Setting the marker to `""` makes the fixture's runner the outermost again.

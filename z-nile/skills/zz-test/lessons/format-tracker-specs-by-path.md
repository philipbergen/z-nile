---
title: Format sequestered specs by their path
when: both
tags: [stylua, format, sequestration, specs]
check: Was every sequestered spec formatted with `stylua <root>/.tracker/issues/<id>` (its own path, again until `stylua --check` is clean right before the mutants and the slow run), not with `stylua .` from the project home, which skips dot-folders?
---
`stylua .` walks the project home but skips dot-folders, so it never touches `.tracker/`. The gate formats and checks `.tracker` only by explicit path, so an unformatted sequestered spec passes a local `stylua .` and fails the gate.

**Why:** c0248's prep: the prototype run found that `stylua .` from the project home skipped the sequestered specs; only naming their folder formatted them.

**How to apply:** after writing or editing a sequestered spec, run `stylua z-nile/.tracker/issues/<id>` (or the project's root), then the format check on that same path.

**Note (c0306's prep, 2026-11-14):** one pass is not always enough. stylua's wrapping of a long `it(` call is not idempotent, so the first pass left a diff. The format stage then failed and aborted a `--slow` run after a batch of mutants had already run on the unformatted file. Run `stylua --check` on the spec folder right before the mutation check and the slow run, and format again until it is clean.

**Note (c0325's prep, 2026-11-15):** running `stylua .` from inside the issue folder silently reformats the specs with another config (the spec hashes changed). Run it from `z-nile/` only. `check.sh --slow` runs the format, lint and type stages before any spec, so one stylua or selene error in an issue folder hides every slow result.

**Note** (c0249 prep, 2026-11-16): run `stylua` from a folder that holds `stylua.toml` (the repository root or `z-nile/`), passing the spec path. Started from inside the issue folder, it does not search the parent folders, formats with its defaults, and rewrites the specs differently on every run.

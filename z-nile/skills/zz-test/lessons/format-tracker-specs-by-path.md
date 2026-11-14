---
title: Format sequestered specs by their path
when: both
tags: [stylua, format, sequestration, specs]
check: Was every sequestered spec formatted with `stylua <root>/.tracker/issues/<id>` (its own path), not with `stylua .` from the project home, which skips dot-folders?
---
`stylua .` walks the project home but skips dot-folders, so it never touches `.tracker/`. The gate formats and checks `.tracker` only by explicit path, so an unformatted sequestered spec passes a local `stylua .` and fails the gate.

**Why:** c0248's prep: the prototype run found that `stylua .` from the project home skipped the sequestered specs; only naming their folder formatted them.

**How to apply:** after writing or editing a sequestered spec, run `stylua z-nile/.tracker/issues/<id>` (or the project's root), then the format check on that same path.

---
title: Load a dependency's sources inside the cases that need them
when: design
tags: [specs, mutants]
check: Does any sequestered spec read a source that only a dependency (or this issue) creates (a `sourceAt` of an adapter, a require of a new module) at the top of the file, so that on a tree without it every case fails to load, and its mutants there "survive" or cannot be judged?
---
A spec file that reads an adapter's source, or requires a module, at its top fails to load as a whole when that file is missing: the runner reports one load error and no case at all. On a partial prototype (this issue's change on main, without a dependency not landed yet) that hides the cases that need nothing missing, and a mutation runner that looks for the row's case failing finds no case and reports the mutant as surviving.

**Why:** f0186's prep (2026-11-15). `price.spec` read f0145's `OfferView` and `TestPurchase` sources at its top. On the prototype cut from main (without f0145), its first case (`Lobby.PRICE`, `Lobby.salePrice`, which need no f0145 code) never ran, and the mutants L5 and L6 "survived". Moving the two `sourceAt` calls into the stub-world builder made the file load, the case run, and both mutants die.

**How to apply:** Read a source, or build a stub world from one, inside the function the cases call, not at the file's top; keep top-level requires to modules that exist on main (or that the issue creates and every case needs). A case whose module is missing then fails alone, on its own line, and the rest of the file still pins what it can.

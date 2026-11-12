---
title: engine/main.luau is at Luau's limit of 200 locals
when: build
tags: [engine, luau]
check: Does this add top-level locals to z-nile/engine/main.luau (at Luau's limit of 200), and are the new helpers in one table or a module so the build still compiles?
---
`main.luau` declares its commands in a `cmd` table and its helpers as top-level locals; a chunk may hold 200. A prototype that added three helpers failed at load, in every fixture, with a syntax error that names no cause.

**Why:** c0282 prototype on c0263's rebased prototype: three `local function`s added to `main.luau` gave "Out of local registers when trying to allocate"; one table (`lifecycle`) with three functions compiled.

**How to apply:** prefer a module (zz-arch: pure over texts) and, when the helper needs main's locals, a single local table. Run any spec after the edit: the failure shows in every fixture.

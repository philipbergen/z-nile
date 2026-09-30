---
id: R0050
type: chore
title: Game alias requires
single: true
issues: [c0390]
design: ready
created: 2026-09-29
---

# R0050: Game alias requires

## Theme
This is a single-issue chore raft for c0390, found during R0040's prep. **It must merge before R0040 starts.**

R0040 (roadmap a2) adds the first adapters that require shared Logic. Server and client adapters sit in different Rojo roots from Logic, and no relative require path resolves both on disk (`tests/meta`) and in the place (the c0020 place rules). Roblox's built-in `@game` alias does, once the repo's two resolvers understand it.

This is test and tooling infrastructure, with no change in game behaviour, so it's a chore. R0040 is a feature raft and can't carry it.

## Whole-raft design
See c0390's Design. The shape:
```
default.project.json ($path nodes) ──graph.gameRoots──▶ { instance = "ReplicatedStorage/Shared", path = "src/shared" }, …
"@game/ReplicatedStorage/Shared/Logic/Session" ──graph.resolveGame──▶ src/shared/Logic/Session/init.luau   (tests/meta, affected)
                                               ──place.resolveRequire─▶ DataModel.ReplicatedStorage.Shared.Logic.Session (c0020 place rules)
                                               ──luau-lsp + sourcemap──▶ already works (E1)
```
- **The contract for R0040**: adapters write `require("@game/ReplicatedStorage/Shared/Logic/<Feature>")`, and `@game` goes **only into ReplicatedStorage** (design-review-001 F2). Within a root they use relative paths or `@self`. Logic never uses `@game`: the meta engine-word rule forbids `game` in Logic.
- **No change to `src/`, `default.project.json` or `tracker/architecture.md`.** `tests/meta` gains one rule (src alias rule, AC5).

## Order & dependencies
One issue, whose implementation steps go graph, then place, then docs. R0040's f0120 and f0130 list c0390 in `depends_on`. R0040's executor starts from origin/main, so R0050 must be merged first. Otherwise R0040's place specs and meta rule fail on the first `@game` require.

## Experiments phase
All run in prep, all PASS: E1 (luau-lsp resolves `@game`), E2 (Roblox documents `@game`, with the citation), E3 (a prototype passes all four acceptance specs plus the existing tooling, place, c0020 and meta specs, and a 17-way mutation check). The executor has no Phase 1 work.

## Exit criteria
Implemented by `check.sh`:
- **RC0**: the full repo gate passes, c0390's `check.sh` passes (AC1–AC5), and `promote-check` passes. The gate now includes the permanent `tests/meta` alias rule.
- **RC1**: `src` requires use only relative paths, `@self/` or `@game/ReplicatedStorage/`. The grep matches single- or double-quoted specs with optional spaces (design-review-001 F6). It's a guard: `src` has no aliased requires today, and R0040's RC3 repeats it for the first real ones.

## Risks & rollback
- **Risk: Roblox rejects `@game` at runtime.** E2 is documented and cited, but R0040's Studio playtest is the first real exercise, and it doesn't block R0040's merge. Rollback is then reverting R0040. A one-minute Studio check retires the risk sooner (see c0390 E2). The fallback, with its duplicate-module cost, is in c0390's Unknowns.
- **Risk: the extra optional argument to `graph.resolve`/`build` confuses a later reader.** It's documented in the function comments. Existing callers are unchanged.
- **Rollback**: revert the PR. Nothing in `src` uses `@game` until R0040.

## Addressed during execution
Review 001 lows (F1-F3) fixed in c0390.

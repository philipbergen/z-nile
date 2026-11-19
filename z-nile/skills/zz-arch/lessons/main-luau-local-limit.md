---
title: main.luau is at Luau's local limit
when: both
tags: [luau, main, locals]
check: Does a change that adds commands to `main.luau` keep its new helpers in one table (or a module) rather than adding top-level locals, since the file is at Luau's 200-local limit? And does a prototype that merges other preps' branches compile `main.luau` on that merge?
---
Luau allows at most 200 locals in one function scope, and `main.luau`'s top level is at that limit. One more top-level `local` makes the file fail to compile.

**Why:** c0250's prototype: `cmd.block` and `cmd.resolve` needed their helpers in one `esc` table. Its revision (prep, 2026-11-13) merged the c0256, c0263 and c0248 prototypes onto `origin/main`: `main.luau` has 199 top-level `local` lines on main and 205 on that merge, before any c0250 code, so the merge did not compile. The prototype moved 11 helpers into one `H` table (194 lines).

**How to apply:** put a new command's helpers in a table local, or better, in a pure module the command calls (the zz-arch rule of pure modules over texts). Count `^local ` lines in `main.luau` on every merge a prototype makes; the executor whose layer first passes 200 owns the fix.

f0339 design review 001 F4 (re-harvested on 2026-11-17, c0369 prep): a design that adds commands to `main.luau` decides where their helpers live, so this applies at design time too (`when: both`).

**Note (R0093 design review 002 F13, 2026-11-18):** the limit is Luau's 200 local registers, and constant locals fold away, so counting `^local ` lines is not the measure (origin/main had 201 such lines, two declaring two names, and ran). `luau-lsp analyze` does not report it; `lune run` does ("Out of local registers when trying to allocate v201: exceeded limit 200"), so it shows as every `./zn` command failing to start. Measure headroom by starting `./zn --help` on the merged tree.

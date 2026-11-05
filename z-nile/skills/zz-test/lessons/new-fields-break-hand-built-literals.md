---
title: A new required field on an exported type breaks hand-built literals in promoted specs
when: both
tags: [types, specs, wiring]
check: Which promoted specs build this type by hand, and does the gate's type stage (not tests/run) still pass for them?
---
Promoted specs build `Lesson` and `Item` tables literally. In strict mode a literal that lacks a new non-optional field is a type error, which `tests/run` never reports but the gate's Lune type stage and `./zn done` do. Make a new field optional and have every reader treat nil as empty, or the chore overrides those specs. Grep the promoted specs for literals of the type, and add a type-check line to the acceptance.

**Why:** c0181 design review 002 F1: `enforcedBy`, `distinct`, `merged` and `Item.dir` were designed as required fields, which would have broken c0111's metrics and harvest specs at the merge gate while the item's own check stayed green.

**How to apply:** `git grep -n 'lessons.Lesson\|lessons.Item' -- z-nile/tests`, then run `luau-lsp analyze` over those folders in the acceptance.

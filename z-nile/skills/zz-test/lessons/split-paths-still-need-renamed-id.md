---
title: A path to a real item folder goes through renamed.id
when: both
tags: [compaction, paths]
check: Does every path a spec builds to a real `tests/acceptance/<id>` or tracker folder map the id through `renamed.id`, besides spelling the path in two parts?
---
Spelling a path in two parts only stops a compaction from rewriting the literal; the folder itself is still renamed, so the spec then reads a missing file.

**Why:** R0045 design review 1 (F3): c0128's specs read `"tests/" .. "acceptance/" .. "f0024/…"`. A compaction moves `f0024` to a new id and leaves split paths alone (`z-nile/engine/compact.luau`), so the specs would fail on a missing file.

**How to apply:** build such paths as `"tests/" .. "acceptance/" .. renamed.id("f0024")`, as c0063 and c0103 do.

c0153 prep: `renamed.id("f0100")` returns f0011, because the compaction map's f0100 is an id from before that compaction and today's f0100 is a later item that reuses the number. `renamed.id` is for ids written before a compaction; for today's ids, write the full `tests/acceptance/<id>/…` path (a compaction rewrites those in every tracked text file) and derive the item folder from it.

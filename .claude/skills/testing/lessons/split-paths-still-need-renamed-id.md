---
title: A path to a real item folder goes through renamed.id
when: both
tags: [compaction, paths]
check: Does every path a spec builds to a real `tests/acceptance/<id>` or tracker folder map the id through `renamed.id`, besides spelling the path in two parts?
---
Spelling a path in two parts only stops a compaction from rewriting the literal; the folder itself is still renamed, so the spec then reads a missing file.

**Why:** R0045 design review 1 (F3): c0128's specs read `"tests/" .. "acceptance/" .. "f0024/…"`. A compaction moves `f0024` to a new id and leaves split paths alone (`scripts/tracker/compact.luau`), so the specs would fail on a missing file.

**How to apply:** build such paths as `"tests/" .. "acceptance/" .. renamed.id("f0024")`, as c0063 and c0103 do.

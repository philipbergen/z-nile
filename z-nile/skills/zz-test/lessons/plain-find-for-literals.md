---
title: Literal text is matched with plain find
when: both
tags: [lua-patterns, specs]
check: Does every `string.find`, `string.match` or `string.gsub` on literal text (an id, a model name, a path, a heading) pass `plain = true` or escape the pattern characters, especially `-`, `.`, `%` and `[`? And is every fixed-string filter on paths (plain find, `grep -F`, `grep -vF`) anchored to the start of the path, where only a prefix is meant?
---
In Lua patterns `-` is a quantifier and `.` matches anything, so `string.gsub(text, "grok-4.7", x)` and `string.find(s, "ab-cd")` do not match the text they name. A spec that does this can fail for every correct implementation, or pass for a wrong one.

**Why:** R0042 design reviews 002 F1 and 004 F3: a skill-name swap and two model-id replacements used hyphenated literals as patterns, so sequestered criteria could not pass. The bug came back after the first fix because only one call was changed.

**How to apply:** use `string.find(s, lit, 1, true)` for searches. For replacement, find the literal with plain find and splice by index, or escape with `string.gsub(lit, "%p", "%%%0")`. Grep the draft's specs for every pattern call on a literal before the first round.

A plain match has the opposite trap: it matches anywhere. A fixed-string filter on paths that means "under this folder" must be anchored to the start of the path: `string.sub(p, 1, #prefix) == prefix`, or `awk -v r="$prefix" 'index($0, r) != 1'` in shell, never `grep -vF "$prefix"`. R0043 design review 002 F3: the stop hook's `grep -vF "$root/"` dropped `tests/lib/tracker/x.luau` because it contained `tracker/`.

c0144 prep: a pattern `^─+$` repeats only the last byte of the three-byte `─`, so the case failed on correct output. Match multi-byte glyphs by removing them (`string.gsub(s, "─", "")` then compare with "") or with utf8 functions, never with a quantifier after the glyph.

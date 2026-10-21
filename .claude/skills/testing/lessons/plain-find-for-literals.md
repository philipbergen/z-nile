---
title: Literal text is matched with plain find
when: both
tags: [lua-patterns, specs]
check: Does every `string.find`, `string.match` or `string.gsub` on literal text (an id, a model name, a path, a heading) pass `plain = true` or escape the pattern characters, especially `-`, `.`, `%` and `[`?
---
In Lua patterns `-` is a quantifier and `.` matches anything, so `string.gsub(text, "grok-4.7", x)` and `string.find(s, "make-issue")` do not match the text they name. A spec that does this can fail for every correct implementation, or pass for a wrong one.

**Why:** R0042 design reviews 002 F1 and 004 F3: a skill-name swap and two model-id replacements used hyphenated literals as patterns, so sequestered criteria could not pass. The bug came back after the first fix because only one call was changed.

**How to apply:** use `string.find(s, lit, 1, true)` for searches. For replacement, find the literal with plain find and splice by index, or escape with `string.gsub(lit, "%p", "%%%0")`. Grep the draft's specs for every pattern call on a literal before the first round.

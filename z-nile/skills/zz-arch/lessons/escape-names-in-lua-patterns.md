---
title: Escape names built into Lua patterns
when: build
tags: [luau, patterns, strings]
check: Does every Lua pattern built from a name (a file name such as `final-review`, an id, a branch) escape the name's magic characters (`-`, `.`, `%`, `+`, `*`, `?`, `[`, `^`, `$`, `(`, `)`), or use `string.find(s, name, 1, true)` instead?
---
In a Lua pattern `-` is the lazy quantifier, so `"^" .. name .. "%-(%d+)%.md$"` with `name = "final-review"` matches `final` followed by zero or more `-` signs and then `review`, not the literal name. It matches the right files by accident and the wrong ones silently.

**Why:** c0248's prototype: the numbering of `final-review-NNN.md` interpolated the name into a pattern, which needed the `-` escaped as `%-` to match the literal name.

**How to apply:** escape with `string.gsub(name, "%p", "%%%0")` before building the pattern, or match plainly with `string.find(text, name, 1, true)`.

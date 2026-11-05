---
title: A "draws X" case finds X from the visible root down
when: both
tags: [adapters, stub-engine, ui]
check: Does each case that says an adapter draws something find it by walking down from the ScreenGui parented to PlayerGui (the one the adapter means), never from a record of Instance.new calls, and does it pin every property the Design's sentence about X names (walk that sentence, not a hand-picked subset), failing for an unparented, invisible, wrongly coloured or wrongly sized X?
---
A stub engine that records every `Instance.new` makes it easy to look a frame up by name. But a frame that is never parented, parented to another ScreenGui, fully transparent or the wrong colour is still in that record, so the case passes while the player sees nothing, or sees it offset by the default insets.

**Why:** R0051 design review 001 F1: f0110's adapter spec found the FIRE and JUMP frames in the `Instance.new` list; with `f.Parent = parent` removed, or the discs made invisible, every spec still passed. f0158 design review 003 F2: the ring's screen setup was pinned by a `ScreenInsets` needle, so a later `IgnoreGuiInset = true` (which resets it in Roblox) passed; the case now reads the drawn Ring screen.

R0051 design review 002 F1 then found the fix had pinned ten of the Design's properties and left out two from the same sentence (the caption's centring and font).

**How to apply:** give the stub a fixed PlayerGui, find the one ScreenGui the adapter names under it, and walk its children. Walk the Design's sentence about the look property by property and pin each one (colour, transparency, corner, caption name, font, alignment, text, size and outline), and run the mutants "unparented", "second ScreenGui", "transparent" and "wrong colour" against a prototype.

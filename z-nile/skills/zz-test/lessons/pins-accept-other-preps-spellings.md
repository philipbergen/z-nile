---
title: Pins of a shared call site accept the other preps' spellings
when: both
tags: [source-pins, in-flight]
check: Does another prep in flight pin the same call site (a Main's boot line) with its own spelling (an argument, an inline require)? Can one source satisfy both pins, and does each pin say only what its own issue needs?
---
Two sequestered pins of one line in different spellings cannot both pass: whichever issue lands second goes red.

**Why:** f0148 design review 001 F4: f0148 pinned a literal `Starts.start()` in the lobby Main, while f0145's prep pins `Paid.start(require("./Starts").start(Paid.allow))`.

**How to apply:** grep every prep worktree in flight for the line, write the pattern so both spellings match (`Starts"?%)?%.start%(`), and pin only the part this issue adds (`.choosing(Bests.choose)` before it).

**Also:** f0148 design review 004 F3: a pin of the lobby client Main demanded the inline `require("./LobbyPicker").new()` with no reason; a local bound to the require failed it. Pin one exact spelling only when another promoted spec already pins it (f0146 pins LobbyView's `.start()`), and say so.

---
title: A pin of a frozen copy of a live file is tied to the live file
when: both
tags: [pins, specs, drift]
check: If the live file changes by one value, does a spec go red, and does that tie stop by a rule (a named change retires it) and not by deleting the case?
from: f0421 code review 005 F8, 2026-11-24
---
A spec that parses a frozen copy of a file proves the copy, not the file. When the criterion says "today's root table", a change to the live file that lands first leaves the pin green.

**Why:** f0421 code review 001 F8 (2026-11-24): AC28 was proven on `root-5e8f5eaa4.models.toml`, a frozen copy of `.models.toml`. No spec compared the two and the watch file did not name `.models.toml`. The pin also called `models.*` only, so the one deliberate change (`sameModel`) was invisible to it.

**How to apply:** add one case that, while the live file has no `[catalog]` (or the condition the pin is about), compares its lines with the expected file, names the change that retires the tie, and put the live file in the watch file. Say in the spec's header what the pin does not cover.

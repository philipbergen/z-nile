---
title: What an unjailed process reads from a folder specs can write is untrusted input
when: both
tags: [jail, untrusted-input, sql]
check: For each file the unjailed gate or orchestrator reads back from a .cache folder, is every field type-checked, does it name its own subject, and does any value reach SQL or a shell as anything but text this module quoted or a number it formatted?
---
A jail denies a spec every write outside `.cache`, but `.cache` is writable, so a file there is whatever the spec wrote.

**Why:** R0081 code review 003 F1: a spec overwrote a sibling worker's results part; `upsertSql` put the record's `seconds` into SQL unquoted, and the unjailed orchestrator ran `ATTACH` and created a database file at the clone's root.

**How to apply:** validate each record field by field, accept a part only if it names its own file, and format numbers (`%d`, `%.6f`) before they reach SQL.

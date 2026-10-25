---
title: Configuration that grants authority is never tracker state
when: design
tags: [security, guards, config]
check: Does any allow-listed path hold a setting that raises a limit, turns on a gate, or changes which tool runs?
---
Tracker state reaches `main` without review, so a setting that lives under a tracker root (an item's `.models.toml` with `auto_merge` or a cap) becomes a way for a step to raise its own limits and turn on its own merge gate. Refuse such files in the one tracker-state function, in any case, and in every gate; they change by a reviewed PR a human merges.

**Why:** c0117 design review 003 F4: a step pushed its issue's `.models.toml` (`auto_merge = ["prep"]`) through the broker, and the next run merged its prep PR against the project's `auto_merge = []`.

**How to apply:** the configuration names beside `.gitattributes`; a broker case and a gate case carrying one.

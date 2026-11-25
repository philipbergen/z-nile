---
title: A new rule in a handler goes before every earlier branch that can replace its record
when: both
tags: [handlers, records, order]
check: For each field the new rule compares, which earlier branch of the same function removes or re-creates the record, and does a case reach the rule through that branch?
from: f0421 code review 006 F1, 2026-11-24
---
A rule that compares a field with the recorded one is skipped when an earlier branch of the function already replaced the record. The rule then holds for the common path and not for the one that matters.

**Why:** f0421 code review 006 F1 (2026-11-24): `register` refused a different model for a process, but the session branch (older than the change) ran first. A second registration with another session id replaced the worker, released its claim as lost and recorded the other model, with no refusal. A review round earlier had missed this branch.

**How to apply:** read the whole function top to bottom before placing the rule; judge it against the worker of the same process (CLI, pid, start time) before any branch can replace it, carry the kept value and its flag onto the new record, and add a case for each replacing branch (another model under another session id: refused and the claim still held).

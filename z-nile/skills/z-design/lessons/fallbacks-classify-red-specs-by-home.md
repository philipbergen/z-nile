---
title: A fallback for a red spec says where the spec lives
when: design
tags: [fallback, overrides, acceptance]
check: For each spec a fallback or an Implementation step says might turn red, is it under `tests/acceptance/` (promoted: a red one is an Override with its chore, so stop and re-prep) or under `tests/tooling/` or another editable folder (fix it in the raft), and does the step say which?
---
A promoted spec under `tests/acceptance/` is never edited during execution, so a red one there needs an Override and a chore in `depends_on`, which an executor cannot add. A tooling spec can be fixed in the raft. A fallback that treats them alike sends the executor down a path it is not allowed to take.

**Why:** d0297 design review 001 F2: E7's fallback said "a red one … is a tooling spec, so a fix in the raft, not an override", but four of the eight specs it named were promoted acceptance specs.

**How to apply:** list each named spec's folder beside it. For a promoted one, the fallback is "stop and send the item back to z-design for an Override"; for an editable one, "fix it in the raft".

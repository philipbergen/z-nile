---
title: A skill edit is placed where the promoted docs specs let it sit
when: design
tags: [docs, skills, specs, overrides]
check: Before the Design adds or moves a paragraph in a skill, has `grep -rlF '<skill path>' tests/acceptance` (and the skill's name) found every promoted docs spec that reads it, and does the planned text keep each exact string, banned string and position those specs pin?
---
Several promoted docs specs pin exact strings, banned strings and the order of steps in the skills. A new paragraph that rewords a pinned line, adds a banned form, or sits between two lines whose order is pinned turns a promoted spec red. That is an Override nobody planned.

**Why:** c0306 prep (2026-11-14). The review-models paragraph had to fit three specs at once:
- `c0116/docs` needs z-design's exact `` `./zn spend <id> --phase design-review --note design-review-NNN` `` and bans `./zn new raft` in z-design;
- `c0114/docs` bans `./zn new raft` with no project in zz-rules;
- `c0111/skill-docs` pins the positions in z-design section 5.

The Design had said only which skills change. Where the paragraph could sit was found while prototyping, and it ended at the close of z-design section 5.

**How to apply:** at the Override check, list the docs specs for each skill in Touched modules, read their pinned strings and orders, and draft the skill text against them. Record in the Design where the text sits and why. Add the docs specs to Affected specs, since the selector does not see a spec that reads a skill as text.

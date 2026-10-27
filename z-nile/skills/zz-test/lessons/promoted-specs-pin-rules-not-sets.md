---
title: A promoted spec pins the rule, not today's set
when: both
tags: [specs, regression, promotion]
check: Does any promoted case assert the exact current set of something later work is expected to extend (skills, folders, links, registry entries, lessons), instead of the rule each member must meet?
---
A spec that says "these are exactly the ten skills" or "pickman's skills hold no lesson" is true on the day it is promoted and turns red the day a planned issue adds the eleventh skill or the first lesson. That issue must then override it, or worse, an unrelated raft's `done` gate goes red.

**Why:** c0115 prep: `layout.spec` first pinned `z-nile/skills` as exactly the ten skills and `.claude/skills` as exactly their links, and said pickman's skills hold no lesson. c0116 adds `z-raft`, and any lesson-writing raft adds a pickman lesson. Rewritten to pin presence of the ten, links equal to whatever folders exist, and no state claim. f0158 design review 003 F3: clear.spec's "every accepted overlap still happens" case, once promoted, would have made d0149's circles or a smaller FIRE an override of f0158; its exactness now runs only at f0158's check and done (an env variable only AC2's check.sh line sets).

**How to apply:** for each set a promoted case reads, ask whether a planned or ordinary change adds to it. If so, assert membership (the named ones are there) and the rule (every member is well formed, the links equal the folders found), never equality with a literal list. Put "this change doesn't make X" claims in `check.sh`, which is not rerun after `done`.

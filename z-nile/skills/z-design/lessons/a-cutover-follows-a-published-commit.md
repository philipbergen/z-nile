---
title: A cutover is judged from a commit ./zn publishes, not from a file's add date
when: design
tags: [migration, git, cutover]
check: Does the cutover survive ready's move of the item folder, a squash merge, a rebase and a commit whose date was set by hand?
---
"Files from before the rule are exempt" needs a before. The date of the commit that added a file is not one: `ready` moves the item folder (the file is added again), a prep lands as a squash (one date for everything), a rebase rewrites dates, and anyone can set `GIT_COMMITTER_DATE`. Work written after the chosen date but before the rule reaches `main` is caught by a rule it could not have known.

**Why:** c0316 design review 001 F3 (2026-11-13): `STAGED_SINCE` exempted a review by the date of its adding commit. c0264's review in `active/` read as added by `tracker: ready R0092`; the acceptance spec itself backdated a commit to make a review old.

**How to apply:** tie the cutover to an event the tracker publishes and cannot be redated: ancestry of the commit that lands the rule, a claim or a ready made after it. Better still, avoid the cutover: make the new field's absence mean the old behaviour, and enforce the field where new work enters.

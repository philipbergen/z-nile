---
title: A validator of an append-only record restricts which rows a direct push may add
when: design
tags: [publish, record, validator]
check: For each event of the record, which writer may put it on main, and does the validator refuse every other writer's event on that path?
---
"Rows are only appended" lets a direct push append a row that belongs to a PR; a wrong implementation of a published command then leaks it onto `main` and every spec stays green.

**Why:** c0263 design review 006 F3: the publish validator accepted any event, and a `status new` that built its append from the worktree's file would have published a rafting PR's `rafted` row.

**How to apply:** list events against writers, make the validator reject the events a published path may not carry, and add a spec case per refused event plus one asserting the PR-only row is absent from `main` after the published command.

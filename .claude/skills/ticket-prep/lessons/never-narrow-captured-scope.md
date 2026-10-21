---
title: Only the user narrows captured scope
when: design
tags: [scope, process]
check: Does every outcome the captured Problem (as on origin/main before this prep) asks for still have a Design and a Checked criterion, and is every outcome removed, deferred or reworded away backed by a `Scope decision (user, YYYY-MM-DD)` line in the Problem?
---
The captured Problem is the scope. Prep adds Solution, Design and criteria and may add detail to the Problem, but it never rewrites, narrows, defers or drops an outcome the capture asks for. When an outcome is too hard, too big, or blocked by today's code, the options go to the user, and the answer is written into the Problem with its date and words. A captured scope too big for one raft is split into sequenced rafts, not shrunk.

**Why:** R0042 (z-nile, 2026-10-20) lost most of its captured scope over five design-review rounds. The move into `z-nile/` became a frontmatter tag, the skill rename became copies, the dispatcher a dry run, and the board lost its live data. Each cut began as a reviewer's recommended fix, was accepted in a refute, and was then written back into the Problem so that the design matched. The user had asked for all of it and was never asked.

**How to apply:** before each round and before `design: ready`, diff each item's Problem against `origin/main` (`git diff origin/main -- <doc>`): only added detail and `Scope decision` lines may appear. For a finding whose only fix is a cut, ask the user before answering it, with the options and what each costs.

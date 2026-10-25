---
title: Only the user narrows captured scope
when: design
tags: [scope, process]
check: Does every outcome in the issue's capture (`./zn capture <id>`: its title, Problem and Solution ideas) still have a Design and an acceptance criterion (Checked, or Judged or Observed only where the zz-test skill allows it), and is every outcome removed, deferred or reworded away backed by a `Scope decision (user, …)` or `Decided with the user (…)` line?
---
The capture (title, Problem and the user's Solution ideas) is the scope. Prep adds the Design and criteria and may add detail, but it never rewrites, narrows, defers or drops an outcome the capture asks for. When an outcome is too hard, too big, or blocked by today's code, the options go to the user, and the answer is written into the Problem with its date and words. A captured scope too big for one raft is split into sequenced rafts, not shrunk.

**Why:** R0042 (z-nile, 2026-10-20) lost most of its captured scope over five design-review rounds. The move into `z-nile/` became a frontmatter tag, the skill rename became copies, the dispatcher a dry run, and the board lost its live data. Each cut began as a reviewer's recommended fix, was accepted in a refute, and was then written back into the Problem so that the design matched. The user had asked for all of it and was never asked.

**How to apply:** before each round and before `design: ready`, compare each item's document with `./zn capture <id>`: only added detail and decision lines may appear in the title, Problem and Solution ideas, and captured Solution bullets stay as they are. An earlier prep's landed rewrite is not scope: restore it, or get a decision. For a finding whose only fix is a cut, ask the user before answering it, with the options and what each costs.

R0044 design review 4 (F2): a design that meets a captured outcome except in rare failure modes (a write that fails for good, an old build) must say so in Risks and name the option that would close the gap for the user, rather than leave the limit unstated or reword the outcome.

c0118 design review 001 (F4): when a Scope decision moves outcomes to another issue, the findings and recommendations that came with them (a programme review's, a reviewer's) must move too, into that issue's document, through a capture `land`; a line in the source item's answers ("c0121's prep must take F3 whole") reaches no one, because the next prep starts from the other issue's document.

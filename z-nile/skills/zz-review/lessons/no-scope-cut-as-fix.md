---
title: A cut is not a fix
when: design
tags: [scope, review]
check: Does any Recommendation make a captured outcome smaller, later or optional, instead of saying "escalate to the user:" with the options and what each costs?
---
A reviewer finds defects; the user owns scope. A Recommendation that removes or defers part of what the issue's Problem asks for reads like a fix, and an author in a hurry takes it. When narrowing is the only fix you can see, the Recommendation is "escalate to the user:" followed by the options (including the cost of keeping the full scope), never the narrowed design.

**Why:** R0042 design review 001 F2 found that a second tracker root was half-wired, which was right, and recommended "(a) shrink scope: keep every item in `tracker/` and add a frontmatter key". The author took (a) in the refute, and the captured move into `z-nile/` was lost. Later rounds kept recommending smaller designs until most of the raft's captured scope was gone, and the user had to restore it.

**How to apply:** for each finding, ask whether the Recommendation still delivers every outcome in the Problem. If it doesn't, rewrite it as an escalation with options. Report a design that has already dropped an outcome without a recorded `Scope decision (user, …)` as high.

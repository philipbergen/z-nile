---
title: A gate on what a reviewer wrote runs when the review is filed, never at landing
when: design
tags: [review, gate, lifecycle]
check: If this review lacks the field the new rule demands, who can legally add it, and when? If the answer is nobody, is the rule checked by the command that files the review?
---
A written review is never edited, and a second review of the same kind is refused. A rule about a review's own content (a line every finding must carry) therefore has one moment when it can be enforced with a way to comply: when the review is filed, by the command the lead runs as the reviewer returns, while the reviewer can still be asked. Checked at landing, the refusal has no fix.

**Why:** c0316 design review 001 F2 (2026-11-13): the design made `status prepared` and `done` refuse a review with a finding that had no `Stage:` line, and told the author to edit `harvest.md`, which could not clear it. Its own spec passed only by rewriting a committed review.

**How to apply:** put the check where the review enters the tracker (the dispatcher's placement, the spend command the lead runs for a subagent's review), let it name the finding, and keep the landing gates to what the author can still change.

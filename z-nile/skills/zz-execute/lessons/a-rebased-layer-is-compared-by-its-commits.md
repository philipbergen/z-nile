---
title: After a rebase, count the layer's own commits
when: code
tags: [restack, rebase, layers]
check: After a rebase or a conflict resolution, is each layer's own commit count compared with what it had before, so that a layer emptied by the rebase stops the run, rather than trusting equal subjects or a clean exit?
---
A rebase that drops a commit as already applied, or a resolution that takes the other side whole, exits clean. Layers are single commits with fixed subjects, so a subject match says nothing about whose work is there.

**Why:** d0434 (2026-11-21, two code reviews): both ways the reviewer found to lose another worker's commit passed a subject comparison; the fix counts own commits per layer and trusts only the tip this clone itself pushed (refs/zn/pushed).

**How to apply:** stop with 'emptied, stop and ask' when the count falls; never decide ownership from a subject, a reflog or a remote-tracking ref.

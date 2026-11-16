---
title: A re-pick that conflicts in z-nile/README.md flips main's Roadmap row in place
when: build
tags: [merge, conflicts, docs, roadmap]
from: c0365 (lesson ticket, withdrawn 2026-11-16)
check: After resolving a conflict in `z-nile/README.md`, does the layer's own issue have exactly one Roadmap row and no *designed* marker left?
---
When a re-pick or merge conflicts in `z-nile/README.md`, flip main's existing Roadmap row and its *designed* marker for the layer's own issue to *exists* in place. Never keep both sides' rows.

**Why:** on 2026-11-15 R0100's re-pick resolved a conflict by keeping main's `designed` Roadmap rows and adding `exists` rows for the same issues. c0264's roadmap-unique spec refuses the duplicate, but no affected gate selected it, so nothing noticed until a full run.

**How to apply:** resolve by editing main's row for the layer's issue, then grep the README for the issue id: one Roadmap row, no *designed* marker. Run the roadmap-unique spec directly, since the affected gate may not select it.

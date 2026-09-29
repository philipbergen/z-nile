---
name: make-issue
description: Capture a new feature/defect/chore issue in the tracker backlog. Use when the user describes work to be done, a bug, or a chore ("add an issue", "we should", "bug:").
---

# Make an issue

1. **Classify the work**:
   - **feature** (`f`): new player-facing or developer-facing capability.
   - **defect** (`d`): behavior that's wrong compared with an issue that's already done or with an obvious expectation. This is rework, and it's counted against the 20% target, so classify honestly.
   - **chore** (`c`): tooling, refactors or infrastructure, with no change in behavior.
2. **Create it**: `scripts/tracker.sh new issue <f|d|c> <kebab-slug>`. The slug is 2–5 words describing the outcome.
3. **Fill in the frontmatter**: `title`, and `depends_on` (IDs) if you already know them.
4. **Fill in only these sections**:
   - **Problem**: the user's words, sharpened. Who is affected, what happens now, and what should happen.
   - **Non-goals**: whatever came up and belongs elsewhere.
   - A few bullet-point ideas under Solution, if they came up.
   Everything else is left for `ticket-prep`. Keep `design: draft`.
5. **Duplicates**: look for overlaps with `scripts/tracker.sh list backlog`. If there's an overlap, say so and ask whether to merge.
6. **Commit to main**, since tracker-only changes don't need a PR: `git add tracker && git commit -m "tracker: new <id> <title>"`, then push. Report the ID and path.

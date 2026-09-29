---
name: metrics
description: Report cost per issue (agent active time, lines) and the rework rate against the 20% target. Use for "metrics", "spend", "how much rework".
---

# Metrics

1. Run `scripts/tracker.sh metrics`. It covers done issues; add `--include-active` for work in progress. It prints:
   - cost per issue: lines added and removed, and agent-minutes;
   - totals and minutes per issue, by type;
   - **Rework %** = defect ÷ (defect + feature), measured by lines added, by issue count and by agent time. Chores are excluded, and that includes every CI and test fix, even ones that are bugs. The target is **under 20%** on all three.
2. **Interpret it for the user**:
   - Which of the three measures is over target, and which defects drove it. Read each defect's Problem section to find the feature issue or raft it was reworking.
   - Patterns: a design area that keeps producing defects, criteria that let defects through, or experiments that should have been run.
   - Suggest concrete process changes, for example a new review checklist item, a meta spec, or a stronger acceptance proxy. Offer to file them as chores.
3. **Don't commit the report.** It's computed on demand, which avoids merge conflicts. The source of truth is each issue's `spend.md`.
4. **Caveat**: spend is best effort. Minutes come from `--time` when the agent knew them, and otherwise from commit gaps capped at 45 minutes. Say so if precision matters to the question.

---
name: metrics
description: Report cost per issue (agent active time, lines) and the rework rate against the 20% target. Use for "metrics", "spend", "how much rework".
---

# Metrics

0. Run `scripts/tracker.sh sync --fetch` first (it only updates `origin/main`).
1. Run `scripts/tracker.sh metrics`. It covers done issues; add `--include-active` for work in progress. It prints:
   - cost per issue: lines added and removed, agent-minutes, and tokens;
   - totals and minutes per issue, by type;
   - **spend by phase**, in lifecycle order, and the same minutes per raft, so a phase that dominates is visible;
   - **design-review cost per round**: minutes and tokens of the `design-review` rows divided by the raft's design-round count, for every raft that has one. For each issue it reads the working-tree `spend.md` and, when this checkout is the git toplevel, the single `origin/main` blob. When one side's rows are a prefix of the other's it uses the longer, so a prep checkout prices a round whose rows were published while the round file is still local, and a branch keeps rows it has not merged. It does not fetch and it does not merge. A ledger that does not parse is reported and that issue is skipped; two blobs, or two ledgers that have diverged, are reported and skipped;
   - **review rounds per raft**, for every raft in any state: design and code rounds, and `format`, the finding format of the raft's first design review (`classic`, `second-order` or `none`);
   - **Rework %** = defect ÷ (defect + feature), measured by lines added, by issue count and by agent time. Rework counts every phase, capture to deliver. Chores are excluded, and that includes every CI and test fix, even ones that are bugs. The target is **under 20%** on all three.
2. **Interpret it for the user**:
   - Which of the three measures is over target, and which defects drove it. Read each defect's Problem section to find the feature issue or raft it was reworking.
   - Review rounds: compare design rounds between `classic` and `second-order` rafts, and say whether the second-order ones need fewer. Treat backlog and active rafts as incomplete: they may have rounds to come.
   - Patterns: a design area that keeps producing defects, criteria that let defects through, or experiments that should have been run.
   - Suggest concrete process changes, for example a new review checklist item, a meta spec, or a stronger acceptance proxy. Offer to file them as chores.
3. **Don't commit the report.** It's computed on demand, which avoids merge conflicts. The source of truth is each issue's `spend.md`.
4. **Caveat**: spend is best effort. Minutes come from `--time` when the agent knew them, and otherwise from commit gaps capped at 45 minutes. Tokens are best effort too: an agent that does not know them leaves `--tokens` out, and that cell stays empty and sums as 0. Say so if precision matters to the question.

# Idea review 001

## Findings

- F1: The first and third Solution sentences are false as written. They say the raft plan keeps adding any same-type, same-project prepared issue to a raft until the sum would pass 3,000 lines, and that an issue of 1,500 to 3,000 lines can share a raft whenever the sum stays at or under 3,000. In `z-nile/engine/raftplan.luau`, though, features join a raft only when they share a surface (an overlapping Touched path). A `solo: true` issue is always a raft by itself, and so is an open raft marked `single`, which never takes another issue. A rafter reading these sentences would put two unrelated features together, or add issues to a solo raft. The Non-goals protect only "never mixes types or projects" and the argument forms, so nothing says these other rules stay. The real change is one number: `raftplan.CAP = 1500` becomes 3000, and the two skill lines change with it (`z-design/SKILL.md:46`, `z-raft/SKILL.md:18`). The Solution should say only that, and add Non-goals that keep the shared-surface rule for features, the solo rule and the single-raft rule unchanged.

## Verdict

revise

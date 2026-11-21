# Idea review 002

## Findings

- F1: The second Problem sentence is false for defects and chores, and the fourth Solution sentence's "always" depends on it. `raft-plan` already puts every prepared defect into the lowest open defect raft that fits under the 1,500-line cap, and does the same for chores, whether or not they are linked (`z-nile/engine/raftplan.luau:6`, `z-nile/skills/z-raft/SKILL.md:16`). So two unlinked defects already land in one raft today, and only features land apart as the sentence says. Because of that, the claim that "a raft whose tickets have no dependency or path overlap between them always has a guess" fails for those defect and chore rafts, which `raft-plan` makes with no guess. It also fails for rafts a person groups with `z-raft c0001 c0002` or `recombine` (`SKILL.md:22`). The problem and the guarantee need to be limited to features, or to merges the worker makes.

## Verdict

revise

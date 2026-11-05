---
title: Instructions must be runnable where they are read
when: design
tags: [skills, worktrees]
check: Can every agent told to do this do it from where it runs and in the role it has (a read-only main checkout, a capture that lands only issue documents, a reviewer or stream subagent that may not publish), and without breaking a project rule? And does every step that runs specs before the issue's code exists name the cases expected to pass then, and what a failure means?
---
An instruction added to many skills has to fit each skill's context. Writing a file is impossible in the main checkout, cannot land through a capture, and is forbidden to a reviewer. Where the action cannot happen, route it to something that can land (an issue, the author's harvest).

**Why:** R0040 design review 1 (F5): every skill was told to write lesson files when it finished, but only the prep and raft worktrees can carry them.

R0040 design review 2 (F3): the fix routed those skills to `./zn new issue`, which subagents (stream implementers and reviewers, handed the same skills) may not run. Skills are read by agents in different roles, so the split has to be by role, not by skill.

R0040 design review 3 (F1) found the fix still split by skill: one agent follows several skills at once (a prep author reads the design skill and the zz-test skill), so two skills gave it contradictory instructions. The rule that held was one paragraph, identical in every skill, keyed on role.

**How to apply:** for each skill a change touches, name every role that reads it (lead, stream subagent, reviewer), its working directory and what it may write or publish. Write one instruction keyed on role, the same wherever it appears, rather than a variant per skill.

c0120 code review 001 F2: the build's redo list said "rebase onto c0114, re-run the classification for new captures", which leaves out the `done`s the freeze and Guess 4 (a) put on main first (R0034, R0012, with their promoted pickman folders). Rebasing over them conflicts inside the renames-only commit. Redo steps for a stacked build start from the stop conditions and regenerate mechanical commits on the new base instead of rebasing them.

f0126 design review 008 F3: step 1 ran f0126's touch specs "first", on dependency code without any f0126 code, where 10 of 13 cases must fail, and also said to stop on any failure.

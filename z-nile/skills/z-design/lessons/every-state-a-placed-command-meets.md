---
title: A command that changes where it acts lists every state the item can be in, and where each skill runs it
when: design
tags: [lifecycle, placement, skills]
check: When a command changes where it acts, has the design listed every lifecycle state the item can be in (in prep, prepared, active in a raft, done) and the worktree each skill runs the command from in that state, and does each pair have a rule and a case? And when the design hands a dispatched path to a layer below (a block, a resume), has it walked the dispatcher's own facts through every worktree the path leaves behind (the open list it reads from the run's last worktree, before any step), not only the commands the skill names? And is a worktree an instruction removes, or a copy of a document older than origin/main's, still what the dispatcher reads (its `st.worktree`), and does a chain case on the fake CLIs walk it, rather than declining the case because the code is a lower layer's?
---
Moving a command from "the checkout it runs in" to "wherever the item is" changes its answer in every state the item passes through, not only the one the change was asked for.

**Why:** c0369 design review 002 F2: `./zn approve` was designed for a design in prep and for one merged to origin/main, but zz-execute also asks the person to run it again on a raft's layer branch when the contract changed; from elsewhere it said "already approved on origin/main" while `done` refused, and inside the layer worktree it pushed the layer branch on the person's behalf.

**How to apply:** grep the skills for every step that runs the command (`git grep -n '<command>' -- '*/skills/**'`), write a table of state, worktree and expected effect, and give each row a rule, a case and, when it needs a worktree the user's decisions do not read, a question to the user.

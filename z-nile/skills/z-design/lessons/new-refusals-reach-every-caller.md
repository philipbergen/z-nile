---
title: A new refusal in a command is checked against every caller that builds its arguments
when: design
tags: [commands, refusals, batches]
check: Who else builds this command's arguments (a plan, a batch, a script, another command), and what does each do when the new refusal fires: does a batch stop half applied?
---
A command that gains a refusal is also run by other code that derives its arguments, and that code was written when the argument could never be refused. A batch that runs it op by op then stops halfway, with the ops before it already published.

**Why:** c0135 design review 001 F2: `new issue` and `new raft` began refusing a used slug, while `raft-plan --apply` builds `new raft <first issue's slug>` for each planned raft. A raft that keeps an old slug (emptied, retired, done) would have stopped a plan after its earlier rafts were made.

**How to apply:** search for every producer of the command's arguments (`git grep` for the command's name and its argv shape) and give each the same rule from the same function, deciding the whole batch before anything runs (here: `raftplan.commands` picks a free slug for every planned raft).

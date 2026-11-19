---
title: A command that chooses by precedence is specced again in the state its first run leaves
when: design
tags: [precedence, idempotence, specs]
check: For each place a precedence-choosing command can act in, does a case run it a second time in the state the first run left (for every pair of candidates that can coexist), and does that second run act on nothing new? And when the second run acts on a branch (a push, a retry), does it act on the branch the placement judged, by its name, rather than on whatever the checkout has checked out by then, with a case that moves the checkout between the two runs?
---
A rule that picks one of several candidates in order (a worktree, origin/main, a retry) is usually specced once per candidate, each from a clean state. The first run changes the state: it records, pushes or publishes, and the candidate it took moves to another list. The second run then meets a combination no case built.

**Why:** c0369 design review 002 F1: after `./zn approve` recorded in the prep worktree and pushed it, the prep moved to the "pushed" list, which came after origin/main in the order; with main holding an older ready design, the second run approved and published that older design, which nobody was looking at. Every case had main holding a draft, so none met it.

**How to apply:** for each candidate the first run takes, write the state it leaves, list the other candidates that can coexist with it, and add a case that runs the command again there (from each place a person runs it from); assert that nothing new is recorded or published. Add the mutant that moves the taken candidate's check below the others.

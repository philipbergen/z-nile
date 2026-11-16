---
title: A liveness rule names every state in which a claim is held but not worked
when: design
tags: [claims, heartbeat, liveness]
check: For each state in which a claim's stamp stays on origin/main (a PR waiting for merge, a dispatcher gate, a readied raft not started, a question to the user), who proves it alive, and if no one does, is it meant to read as lost?
---
A lease that expires when nobody pushes proof of life marks every claim parked at a PR, a gate or a question as dead, and a pick-lost-first rule then hands finished work to the next agent.

**Why:** c0265 design review 001 F1: a claim's stamp stays on main from the claim to the merge, long after the session that held it ended; c0118 was such a claim.

**How to apply:** list the states between claim and merge, say which fact parks each (an open PR naming the item, a `questions.md`), and keep unknown out of the lost verdict.

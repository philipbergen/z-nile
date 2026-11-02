# Proposed lessons (R0068, raft coherence review 001)
The rafting lead was a subagent and does not write lesson files. These are the texts for the lead to write under `z-nile/skills/z-raft/lessons/`; harvest.md names both.

## z-raft/plan-the-switch-over
```
---
title: A raft that changes its own process rules plans the switch-over
when: design
tags: [raft, order, harvest, emergent]
from: R0068 design review 001 F1, F2, F3
check: Does any member change a rule that the raft's own records or RC lines are judged by (harvest grammar, review format, sequestration checks), or judge the whole repository in a way an emergent issue in the same raft would break, and does the raft document say what is converted after that member merges and when?
---
A member that changes how reviews and harvests are written or checked changes the raft's own `harvest.md`, its reviews and its RC lines mid-raft, and a member check that compares the whole repository to the merge base goes red on the first emergent issue (a new `check.sh`).

**Why:** R0068 (c0136 changes the harvest grammar; c0173 and c0174 carry strict merge-base checks): the raft's earlier records became unattributed or uncovered the moment c0136 merged, RC2 claimed more than it read, and an emergent issue would have blocked `done`.

**How to apply:** name each record the raft writes before the rule changes and who converts it after the merge; read what an RC command's argument really judges (`--unattributed R0068` reads the raft folder only); keep members with whole-repository checks out of rafts that may create an emergent issue.
```

## z-raft/member-handshakes-reach-the-order
```
---
title: A member's pending handshake with another prep is a step in the raft's Order
when: design
tags: [raft, order, handshake]
from: R0068 design review 001 F4
check: Does any member's design say "action for the lead, before X is readied", and does the raft's Order & dependencies carry that step with its escalation?
---
`ready` and the lead follow the raft document, not the members' designs, so a pre-ready action recorded only in a member's design is dropped.

**Why:** R0068 design review 001 F4: c0136 requires a handshake with c0166's prep before it is readied; the first R0068 Order never mentioned it.

**How to apply:** grep each member for "Handshake", "before .* is readied" and "action for the lead"; copy each into Order & dependencies with who acts and what happens if they decline.
```

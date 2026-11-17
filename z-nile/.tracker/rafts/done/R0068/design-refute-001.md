# Answers to design review 001 (R0068)

Each finding is accepted; the fix is in R0068.md.

### F1 [medium] RC2 judged less than the prose said: fixed
`--unattributed` takes item ids as `--uncovered` does, so RC2 reads this raft's own `harvest.md` only. Exit criteria and Risks now say so: RC2 covers the raft folder, and the members' ungrouped prep entries are attributed by c0112 (R0069), which the gate invariant needs anyway. RC2 is kept as it was. Consequences: none; no member's `harvest.md` is edited here (it is part of each member's `grouped:` record).

### F2 [medium] c0136 changes the harvest rules mid-raft: fixed
A Risks bullet now names the switch-over: right after c0136 merges, the lead turns the raft's old-form notes into one entry per finding, adds steps to the rest, and briefs wave-3 stream reviewers from the merged zz-review skill; adding a step to an old `stream-review` note is refused by c0136's own check.

### F3 [medium] c0173 and c0174 go red on an emergent issue: fixed by regrouping
`./zn unfold R0068 c0173 c0174`; they are now R0078, a raft of their own (design review in that raft). R0068 keeps c0122, c0136, c0138, c0156; its Theme, size (1,022) and Risks are updated. Consequences: R0078 needs a coherence round (two issues), run; R0068's record changed by an unfold alone, which needs no new round.

### F4 [medium] the c0166 handshake was not in the Order: fixed
Order & dependencies now has a "Before `./zn ready R0068`" step with the escalation to the user and the c0136 unfold if the user picks (b).

### F5 [low] other dependents: fixed
The cross-raft paragraph now lists c0166 (`depends_on: [c0136]`, preparing) and c0227 (`depends_on: [c0118, c0138]`, new) beside R0069 and R0074.

### F6 [low] reason for c0136 before c0138: fixed
The Order and the zz-rules bullet now give the real reason (adjacent `lessons` and `capture` rows; c0138's patch context goes stale; apply its row by hand) and say the `trail.luau` hunks are far apart.

### F7 [low] user decisions: fixed
The Theme quotes c0136 "Fold into c0136" (2026-10-25) and c0156's 2026-10-25 decisions. c0174's "In the prep commit" moved with it to R0078.

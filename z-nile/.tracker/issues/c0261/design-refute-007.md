# Design refute 007: c0261

Answers design-review-007.md (the round the user asked for after the final one). No high.

- F1: fixed: Implementation steps 6 and 7 name the list read, its fence, the fail-open rule and the `missing` attempt, with the cases tests first (a fake agent without Opus starts kimi; a failing list starts Opus; read once per run); a Rules row (`reasoned`: wiring not prototyped); Open question 7 carries the three escalated paths. Consequences: a new fake agent answering `--list-models`; c0117's fakes answer none, which fails open, so they stay as they are.
- F2: escalated: Open question 8 (keep the members' cutoff, the default, or bind a raft when any member row carries its prefixed subject), with the in-flight window described.
- F3: fixed: on a failed write from the author's worktree the dispatcher prints the exact `./zn spend` line and keeps nothing pending (no double write); a failing publish is not staged (reasoned).
- F4: fixed: the escalated paths are numbered 1 to 3, step 8 no longer lists the raft's own round, the main-checkout refusal is `modelStep`'s.

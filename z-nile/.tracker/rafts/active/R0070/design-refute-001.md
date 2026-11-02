# Answers to design review 001 (R0070)

The verdict was "unfold c0189, then approve after fixes". c0189 is unfolded (`./zn unfold R0070 c0189`) and R0070 is a raft of c0194 alone; R0070.md is rewritten for it. c0189 stays prepared with no raft; it needs a new prep (z-design), which the lead and the user order. No member design was edited.

### F1 [high] the prototype rule contradicts itself: accepted
Needs a change of c0189's design (its pinned `RULE`, the hook message, a `lacks` for "or the scratchpad"; c0194's step-8 note under c0189.md is out of date because c0189's prep is finished). Fix: c0189 unfolded; the definition its re-prep must take is recorded in R0070.md (Whole-raft design, "To c0189") and Risks.

### F2 [high] c0194's `callers.spec` fails on c0189's `mktemp`: accepted
Fix by c0189's re-prep (avoid `mktemp` in its install) or a one-entry allow-list in c0194's `callers.spec` (a c0194 change the user may choose); recorded in Risks. Not a problem for R0070 as it now stands: nothing else of this rafting writes `mktemp` into `main.luau`.

### F3 [medium] "c0194 first" is enforced by nothing: accepted
The Order no longer claims z-ready checks it; it states the gap and the fix (`depends_on: [c0194]` on c0075, a change to c0075's design, left to the user). R0073's "simpler after R0070" is stated as not required.

### F4 [medium] RC2 vacuous and slow: accepted
RC1 and RC2 removed; with one member the raft adds no RCn and Exit criteria say so.

### F5 [medium] Theme omitted c0189's decisions: moot
c0189 left the raft; its decisions travel with its document (the four decided and two pending ones are for its re-prep and the user).

### F6 [low] gate inside `./zn tmp jail` fails at c0189's hooks stage: moot, noted
Recorded in Risks for c0189's re-prep.

### F7 [low] statements that did not match the members: fixed
The rewritten Whole-raft design is a single-member document and quotes the interfaces from c0194 only.

### F8 [low] c0157: fixed
Named in the Whole-raft design (c0157 is being prepared on the same skill lines; c0194 adds a dated note under c0157.md).

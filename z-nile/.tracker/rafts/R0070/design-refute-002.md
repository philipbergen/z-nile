# Answers to design review 002 (R0070)

The verdict was "changes". F1 needs c0189's design to change; the fold is the user's request, so c0189 stays in the raft and F1 is recorded under `## Open to the human` in R0070.md for the user. No member design, check.sh or acceptance spec was edited.

### F1 [high] c0189's wiring.spec cannot pass on current origin/main: refuted as a raft-level fix, recorded open
Accepted as true (the evidence is a stacked run). The fix is a change to c0189's design, which this skill never edits and which the user's fold request does not let me unfold on my own judgement. R0070.md (Order, Risks, Whole-raft design) now says what is true (9 files, 13 hunks; two pins name removed text; tooling merges red until `./zn hooks` runs). Decision for the user is under `## Open to the human`: unfold c0189 for an amendment and re-approval then fold again, or keep it and accept layer 2's first stop.

### F2 [medium] six hook cases fail on the dispatch wrapper until R0096 lands: accepted
Order & dependencies names the wait for R0096 (d0298), the executor's stop rule and the `./zn find R0096` check.

### F3 [medium] the step-8 note under c0189.md breaks its approval: accepted, partly open
The executor skips the c0189 half of step 8 (Whole-raft design) and the conditional Risks bullet is removed. The edit of c0189.md:134 changes its design and goes with F1 (open).

### F4 [low] stale facts: fixed
G1 decided, both approvals on record, R0078 done, R0131 done and layer 1's questions.md answered by it, the merge's clone applies to a game PR only.

# Answers to design review 001 (R0078)

All four findings accepted; no member design changes. Fixes are in R0078.md, check.sh and R0070.md.

### F1 [medium] order against R0070 only in R0078; reverse order breaks c0173: fixed
R0078 must be merged before R0070's PR merges (not just readied). R0070.md now says R0070 waits for R0078 and carries the placement rule for c0194's note under c0075.md (after the first paragraph or at the end of Design, never directly under `## Design`; R0039.md not edited). R0078 states the tested failure and the safe reverse order. Consequences: R0070's executor follows a placement rule that no check enforces; the review of R0070's code reads it.

### F2 [medium] wrong reason for "before R0039 and R0030": fixed
The Order now says the corrections are already on `origin/main`, and gives the real reason (a re-prep of c0075/c0083 or a compaction would move the blob pins and stop the patches applying, so R0078 could never be done) and an escalate-to-the-user recovery in Risks.

### F3 [low] unchecked claims: fixed
"Execution changes no file outside the two items' own folders" now names the raft's folder too, and RC1 pins it with a diff against the merge base (path pattern tried on sample paths).

### F4 [low] no stacked branches: fixed
Risks forbid stacking R0078's branch on another raft's branch.

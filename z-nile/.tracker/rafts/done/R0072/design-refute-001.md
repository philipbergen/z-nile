# Answers to design review 001 (R0072)

All six findings are accepted; the fixes are in R0072.md and check.sh. No member is unfolded and no member design changes.

### F1 [medium] second `bounded.pl`: fixed
The Whole-raft design now says c0181 (R0074) writes the same path with another contract and lists the four properties R0072 needs (`--time N --`, exit 124/125, `cpu.sh`, a child that survives a stdin that is not a live pipe). Both executors check them at step 1 when R0074 lands first and stop and report if one is missing; the lead tells R0074's lead the call shape to keep. Consequences: the reconciliation itself stays in R0071/R0074.

### F2 [medium] the loop lint gates in-flight work: fixed
Risks now lists the rafts and unrafted items whose Touched modules cover Luau files (from the review's search) with the rule "whichever lands second lists its loops in `loops.ALLOWED`; a moved loop moves its entry"; the lead tells the R0068, R0074, c0180 and c0165 leads. The mirror sentence in R0074.md ("Takes from R0072: the loop lint") is added there.

### F3 [low] c0136 and c0165: fixed
Two bullets added to the Whole-raft design (lead groups c0193's entries at Phase 5 if c0136 lands first; c0193's tree-reading cases declared always-run if c0165 lands first). Not a member change.

### F4 [low] only c0192's lesson names its meta case: fixed in the text
The R0074 bullet states the difference, gives c0193's c0181 ref and the 1,200-byte cap; matching the forms would unfold c0193 and is not done.

### F5 [low] RC1: fixed
RC1 now checks `--when design` and `--when build` for each lesson with an anchored `grep -q '^- <skill>/<slug> ('` (tried on an existing lesson and a missing one).

### F6 [low] stale numbers: fixed
c0191's loops are quoted as 15 (11, 2, 2) with "rerun the search"; sizes marked as estimates; Rollback lists the SKILL.md edits and the promoted specs and the revert conflict.

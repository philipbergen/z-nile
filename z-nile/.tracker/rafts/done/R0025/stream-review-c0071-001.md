# Review 001: c0071 (stream review, code mode)
Inputs: `git diff R0025-ready-raft...ws-c0071` (3 skills + c0071.md log); `tracker.sh check c0071` 6/6; c0037 done check 7/9 (AC2, AC6 red) identically on ws-c0071 and the R0025 worktree, so this stream made nothing worse; pinned tokens, the 13 banned phrases (none in added lines) and `grep round 3|003` (no leftovers) all clean. Diff stays inside the three Touched skills and c0071.md.

### F1 [high] Design review can reach `design: ready` on a refuted high with no reviewer ruling
Where: ticket-prep step 5.4 (first bullet) and step 5.5
Evidence: Round 1 or 2 has a high finding that the author answers `refuted`. 5.4 re-runs only when a high was "fixed" or the design changed materially, so no round follows. 5.5 now accepts "every finding in it is answered `fixed` or `refuted`", so `design: ready` is set with an unverified refuted high. The old 5.5 ("approve, or only low findings remain") did not allow this. Code mode avoids it through execute-raft step 6's "refuted any high" trigger; the design side has no equivalent.
Critique: The stop rule is not the same in substance across the two skills, and the design gate is weaker than before. The tempting fix is to add "or refuted" to the first bullet only.
Consequences: Rounds 1-2 then loop on any refuted high up to round 3. After round 3 or 4 a high already makes the round major, so nothing changes there. Round 5 needs the same treatment (F2).
Recommendation: In 5.4 bullet 1, trigger on "any high finding was fixed or refuted, or the design changed materially"; in 5.5 allow `refuted` only for non-high findings unless a later round approved. Add the same wording to c0071's Design and an AC4/AC1 grep for it.

### F2 [medium] Round-5 high answered `fixed` passes the design gate, but blocks in code
Where: ticket-prep step 5.5 vs execute-raft step 7
Evidence: 5.5 sends only "a high still open in round 5" to the user. A round-5 high answered `fixed` is unverified (no round 6) yet counts as answered, so `design: ready` is set. execute-raft step 7 blocks on any high in the final round "whether or not you fixed it".
Critique: The two skills differ on the same case. The issue's Design says "Round 5 with an open high", so the ambiguity is inherited.
Consequences: Fixing it sends every round-5 high to the user, the same as code.
Recommendation: 5.5: "any high in round 5, fixed or not, goes to the user". Mirror execute-raft's wording.

### F3 [medium] "Final round" is undefined for a round that ends early (rounds 1-2), which gates deferral
Where: execute-raft step 4 deferral bullet and step 7; ticket-prep 5.5
Evidence: "Otherwise it is the final round" is stated only for rounds 3 and 4. A review that ends after round 1 or 2 (no step 6 trigger) has mediums or lows. Step 4 allows `deferred` only "left in the final round", and `tracker.sh done` accepts it only per step 7. An agent can't tell whether round 1 or 2 was final, so deferral there is either forbidden or unrulable. Likewise the "final round" in ticket-prep 5.5.
Critique: Needless ambiguity at the exact point JC1 cares about. The fix could be to make deferral legal in any round.
Consequences: Deferral in a non-final round is harmless (the next round exists anyway), but the wording must say so.
Recommendation: Define once: "the final round is the last round run: round 5, or any round after which no further round is required". Use that in step 4, step 7, 5.4 and 5.5.

### F4 [medium] Step 6 is unchanged and now contradicts step 7 for rounds 3-5
Where: execute-raft step 6 ("Re-review ... if any of these are true") vs step 7
Evidence: Step 6 has no round limit. After round 5 with a refuted high, step 6 says re-review, step 7 says final and block. After round 3 with fixes that "changed the design" by wording only, step 6 triggers but step 7's minor definition says stop. The log records "step 6 unchanged" as intended, but step 7 only says "After round 1 or 2, step 6 decides"; step 6 does not say it stops there.
Critique: An agent reading in order hits step 6 first and may run a round 6 or a needless round 4.
Recommendation: Prefix step 6 with "After round 1 or 2 (step 7 governs later rounds)" and, in step 7, state that step 6's triggers are subsumed by "major". Add a grep for it in AC4.

### F5 [low] "Minor" is stricter in code than in design, and "single assertions" and "about 15%" are soft
Where: execute-raft step 7 vs ticket-prep 5.4
Evidence: Only the code text adds the 15% clause and the Judged fail; design has no analogue (fine), but "single assertions" is unbounded (how many?) and "about 15%" is inherited. JC1 passes on balance: severities plus the diff decide, with no "if needed" or "use judgment".
Recommendation: Optional: "at most one assertion or comment line per finding". Not blocking.

Verdict: changes

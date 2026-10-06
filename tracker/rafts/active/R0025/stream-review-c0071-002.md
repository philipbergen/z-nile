# Review 002: c0071 (stream review, code mode)
Inputs: `git diff R0025-ready-raft...ws-c0071` (ticket-prep 5.4/5.5, execute-raft Phase 4 steps 4, 6, 7 and Stop conditions, tracker Merging 1, c0071.md log, round-1 files); `tracker.sh check c0071` 6/6; diff stays inside the three Touched skills, c0071.md and the stream-review/refute files. Rulings on round 1: F1 fixed (5.4 bullet 1 now counts a refuted high), F2 fixed (5.5 sends any high in the final round to the user), F3 fixed (final round defined once in 5.4 and step 7, used by 5.5, step 4 and Merging), F4 fixed (step 6 limited to rounds 1-2, step 7 decides from round 3), F5 refuted and the refutation is right (wording is the issue's own Design, and the reviewer ruled no blocker).

Stop-rule walk, design (5.4/5.5) vs code (Phase 4 steps 4, 6, 7, Stop conditions, Merging 1); each has one outcome, the same in both:
- High fixed in round 1: design bullet 1 and code step 6 both run round 2.
- High refuted in round 2: both run round 3 (new reviewer rules on the refutation).
- Medium-only round 3 with a new spec case: answering adds a spec case, so not minor, so major in both: round 4. Neither skill applies the round-1/2 triggers here.
- Minor-only round 3: both stop; round 3 is the final round; design sets `design: ready` (no high, all answered), code goes to Phase 5 with mediums and lows fixed or deferred. Merging 1 does not block.
- High in round 5 answered fixed: round 5 is always final; design goes to the user, code blocks (step 7, Stop conditions, Merging 1 "significant"), whatever the answer.
- Approve in round 1: design stops and sets ready; code goes to Phase 5 with no refute file. A round 1 or 2 that stops cannot hold a high (a fixed or refuted high forces another round), so a high is reachable in a final round only in round 5.

### F1 [low] Design has no deferral path for a medium that cannot be fixed in the final round
Where: ticket-prep 5.5 vs execute-raft step 7
Evidence: 5.5 sets `design: ready` when every finding in a high-free final round is `fixed` or `refuted`. Code mode allows `deferred <id>` for a medium or low; design mode has no such line, so an unfixable medium must be refuted (a refutation nobody rules on) or goes to the user.
Critique: Not a stop-rule divergence (the outcome is still one of two), and the issue's Design does not ask for deferral in design review.
Consequences: none for this issue.
Recommendation: Optional follow-up; no change needed here.

Verdict: approve

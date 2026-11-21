# Refute 003: R0040
Spend note: the design-review row for round 3 says 8 minutes. The reviewer's usage report says 5 minutes and 132k tokens.

- F1: fixed: this is the third round on the same mechanism, so the mechanism changed rather than gaining a clause. It is now decided by role, not by skill, as one paragraph that is identical in all eleven Lessons sections (only the read command's skill name differs):
  - a subagent reports the candidate in its review or final report and never writes a lesson file or runs `tracker.sh new`;
  - the lead of a prep or raft writes it under the skill the lesson improves (as Files says), with `from:` outside a review;
  - any other lead captures it with `new issue c lesson-<slug>`.
  ticket-prep's and execute-raft's "goes in my own folder" sentences are gone. execute-raft Phase 2B step 2's brief and report list now carry candidate lessons, and Phase 4 step 5 has the lead write the streams' candidates alongside the round's harvest. skill-docs pins the identical paragraph, the three role clauses, the absence of "never writes a lesson file itself", the Phase 2B sentence and the Phase 4 sentence. New rows were run, all killed: one paragraph, lead writes in the improved skill, stream brief, lead writes the streams' lessons. consequences:
  - A lead writes lesson files outside its Touched modules. Spend splits unclaimed files evenly, so this is harmless, as the Design now says.
  - The reviewer's capture clause is still dead text for a reviewer, which is a subagent. That is intended: the paragraph is the same for every reader, and its subagent clause is the one that applies.
- F2: fixed: the AC6 label, the skill-docs header and title, and the Problem bullet now describe the role routing ("reads its lessons and routes new ones by role"). consequences: none.
- F3: fixed: ticket-prep step 5.3 now reruns `scripts/tracker.sh promote-check <R-id>` after the round's spec edits. skill-docs pins it between steps 3 and 4 (row run, killed). The lesson was rewritten as the broader class, `ticket-prep/rerun-skipped-checks-after-edits`: checks the runner skips (type check, promotion dry run, lint, format) are rerun after every edit they guard. Its `check` asks which such checks this draft has. The record-location clause was dropped. The harvest entry for review-002 F1 now names it. consequences: none.

Prototype after these answers: c0111's specs pass (31 cases), `promote-check R0040` is OK, `lessons --check` passes (10 lessons, 18 harvest entries), `--uncovered R0040` covers every finding, and the full gate passes (1821 passed). Of the 62 mutants, 61 are killed, and 1 is obsolete (its rule was replaced in round 1).

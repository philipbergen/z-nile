# Refute 002 (c0274): round 2 answered after the user's decision

Decided with the user (2026-11-09): "Stop records the verdict" (option (a) of F1). `--replace` is gone.

- F1: fixed: `./zn stop` judges the claim it gives back and writes the verdict in its subject (`(claim S)` live or parked, `(claim S, lost <n>m)`, `(claim S, unjudged)`); a worktree re-adopts with a plain `--adopt` only after a stop that recorded it live or parked (one `git log --grep` of origin/main), so a taker's stop of a lost raft leaves the old lead refused for good; consequences: a verdict read in `stop` (fails closed), usage line, zz-rules, z-stop, AC4 and the Rules table lose `--replace` and N4, gain S1 to S3 and S7 and two cases (the owner's live stop and ready, then a lost one), and c0275 must run its branch drop at `stop` after the verdict read (layer rule). The F1 fix was checked against its own consequence: a never-beaten (`nobeat`) claim records `unjudged`, so it fails closed too.
- F2: gone with the flag (its two clauses no longer exist).
- F3: fixed: a takeover restamps every backlog carrier of the old stamp in the one commit (a recombine's other raft, a member), the taker owns every raft among them, one branch and one swap; consequences: Rules row S4 and a case with two rafts sharing a stamp; a member holding a claim of its own under another stamp is still refused with a naming that now says what works.
- F4: fixed: `release` refuses a checkout whose memory reads `taken`, with or without `--force`; consequences: row S5, a case beside the give-back refusals; zz-rules' list of refused give-backs.
- F5: fixed: `dropStamp` removes the claim file `stampMemory` falls back to too; consequences: row S6 and a memory.spec case (a raft given back is never later "taken over").
- F6: fixed: the refusal text now names the working steps ("give it back (./zn status X new) first, then ./zn status R preparing").
- F7: fixed: the taker's branch tips are asserted after the give-backs and the release refusals, the rafting branch too.
- F8: fixed in the layer rule: c0275's first beat after a takeover runs after the swap, and its branch drop at `stop` after the verdict read; the swap keeps its create-only write.
- F9: fixed: the lesson was rewritten at the end of round 2 (look for a fact the engine can read, fail closed).

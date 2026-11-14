# Answers to design review 005: c0263

- F1: fixed: approve.spec's first case ends with a commit of the worktree (the carried move only edits the document), and the refusal case adds a dirty file in another issue's folder as a second `outside` case. Run: approve.spec is green on a prototype of `approve`, the carried refusal and the doors (E12).
- F2: fixed: approve.spec seeds `z-nile/next`. Run on the prototype.
- F3: fixed: publish.spec builds every expected text from the helpers (`one(...) .. row(...)`), not from trimmed `git show` output. Run on the prototype: green.
- F4: fixed: `none` is refused by `isValid` and by `parse`; the pure spec's accepted list lost it and gained the first-add suffix; a parse case refuses an actor `none`.
- F5: fixed: `provenance.union` orders base, then main's new rows, then ours (not `git merge-file --union`); the pure spec expects approved, unblocked, rafted and `appendOnly(theirs, united)` accepts; dispatch.spec adds a row to c0096 on main after the PR is cut and the gate still merges; the Rules table has the row.
- F6: fixed: the order of approve's refusals is stated (worker, main checkout, identity, agent without words, not preparing, design not ready, outside) and the carried move's approval check comes after every existing refusal; approve.spec and dispatch.spec exercise the first two, c0053/commands-claim:107 stays as it is.
- F7: fixed: record.spec adds the conflict case: both sides edit a title and append to the record, `./zn sync` fails naming the document, no `MERGE_HEAD`, `HEAD` and the tree unchanged; and the same two appends without the document conflict are unioned. Run on the prototype: green.
- F8: fixed: `unblocked` is hidden per commit: a `tracker: <id> new` commit that also changed the item's record is covered by its stored row, any other prints as derived; the pure spec has the pair and who.spec an old give-back plus a newer one that wrote the row (two lines, one `(from git)`, one stored).
- F9: fixed: `merged` is the commit's author (`human:<author> (from git)`), trailers ignored; the pure and who.spec cases expect it; the claim that both agent and merger are on the record now rests on `delivered` (agent from the trailer) beside `merged` (author).
- F10: fixed: `rafted` is derived from the newest life commit whose subject names the current raft id as a word (66 of 85 rafts, E11), not from one subject shape; an idea taken from a first add is marked `(from git, first add)`, with a who.spec item (c0040).
- F11: fixed: record.spec adds `./zn record` on a raft (`R0130 unblocked`) and on an active item (`c0090 unblocked` published, `confirmed` refused), with a seeded active raft. Run on the prototype: green.
- F12: partly fixed: the cheap wiring was prototyped (E12) and approve, publish, record and lifecycle specs run green on it; the dispatcher, `who`, the board and `trail`'s log format stay `reasoned`, said so in Rules and mutants.
- F13: fixed: the pure spec refuses a row with three cells, a bad `when`, a missing closing bar and an actor `none`, both by `parse` and by `problems`.
- F14: fixed: cross-references corrected ("open question 2").
- F15: fixed: z-design's step 5 text is specified: commit the lessons and architecture changes outside the folder, then `./zn approve`, then `status prepared` and the prep commit; the prep spend row counts the approve commit.
- F16: stated: open question 1 says that option (a) records that the user said yes, not that the user ran it, and recommends (b) if the human must run it.
- F17: fixed: `who` and the board take `people` from the same pass over the same log.
